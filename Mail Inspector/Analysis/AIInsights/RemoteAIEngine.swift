//
//  Mail Inspector
//
//  Copyright (c) 2026 Nicholas K. Dionysopoulos
//  Licensed under the MIT License. See license.txt in the project root for details.
//

import Foundation

/// An HTTP-based `AIAnalysisEngine`, parameterized by an `AIProviderDefinition` — used for
/// LM Studio, Custom (OpenAI-compatible), and, once added, the hosted catalogue. Carries no
/// `@available` annotation: unlike Apple's on-device model, nothing here needs macOS 27.
///
/// Unlike `OnDeviceAIEngine` (which lets `LanguageModelSession` manage its own transcript), this
/// backend is genuinely stateless per HTTP request, so this engine owns conversation history
/// itself — `history`, replayed on every `streamRespond` call, capped to the last
/// `maxHistoryTurns` so a long conversation doesn't grow past what a smaller local model's
/// context window can hold. The score call never touches `history` at all (a fresh, one-off
/// request each time), for the same reason `OnDeviceAIEngine` uses a throwaway session for it:
/// keeping a structured JSON exchange out of the conversation the model will later continue in
/// plain text.
@MainActor
final class RemoteAIEngine: AIAnalysisEngine {
    private let definition: AIProviderDefinition
    private let endpoint: String
    private let apiKey: String?
    private let model: String
    private let systemPrompt: String
    private var history: [ChatTurn] = []

    private static let maxHistoryTurns = 20

    init(definition: AIProviderDefinition, endpoint: String, apiKey: String?, model: String, systemPrompt: String) {
        self.definition = definition
        self.endpoint = endpoint
        self.apiKey = apiKey
        self.model = model
        self.systemPrompt = systemPrompt
    }

    var capabilities: AIEngineCapabilities {
        AIEngineCapabilities(
            supportsStreaming: true,
            supportsModelListing: definition.modelsPath != nil,
            requiresApiKey: !definition.apiKeyOptional,
            requiresEndpoint: definition.isEndpointEditable
        )
    }

    func generateScore(signalsSummary: String) async throws -> AIScoreResult {
        let prompt = """
            Here is the computed signal digest for this email:

            \(signalsSummary)

            Assess how legitimate this message is. Respond with ONLY a single JSON object of the \
            exact shape {"score": <integer 0-100>, "rationale": "<one or two sentence rationale>"} \
            and nothing else — no markdown code fence, no extra commentary, no other text.
            """
        let body = AIOpenAICompletionsWire.requestBody(model: model, systemPrompt: systemPrompt, history: [], newPrompt: prompt, stream: false)
        let data = try await performRequest(path: definition.chatPath, body: body)
        let text = try AIOpenAICompletionsWire.parseNonStreamingContent(data)
        return try AIOpenAICompletionsWire.parseScoreResult(text)
    }

    func streamRespond(prompt: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let body = AIOpenAICompletionsWire.requestBody(model: model, systemPrompt: systemPrompt, history: history, newPrompt: prompt, stream: true)
                    var accumulated = ""
                    try await performStreamingRequest(path: definition.chatPath, body: body) { delta in
                        accumulated += delta
                        continuation.yield(accumulated)
                    }
                    history.append(ChatTurn(role: .user, text: prompt))
                    history.append(ChatTurn(role: .assistant, text: accumulated))
                    if history.count > Self.maxHistoryTurns {
                        history.removeFirst(history.count - Self.maxHistoryTurns)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: Self.wrapError(error))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func listAvailableModels() async throws -> [String] {
        guard let modelsPath = definition.modelsPath else { return [] }
        let data = try await performRequest(path: modelsPath, body: nil)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json["data"] as? [[String: Any]] else {
            throw AIEngineError(message: "The provider's model list wasn't in the expected format.")
        }
        return items.compactMap { $0["id"] as? String }.sorted()
    }

    // MARK: - HTTP plumbing

    private func resolvedURL(path: String) throws -> URL {
        let trimmedBase = endpoint.hasSuffix("/") ? String(endpoint.dropLast()) : endpoint
        let normalizedPath = path.hasPrefix("/") ? path : "/\(path)"
        guard let url = URL(string: trimmedBase + normalizedPath) else {
            throw AIEngineError(message: "The configured endpoint isn't a valid URL.")
        }
        try AITransportPolicy.validate(url)
        return url
    }

    private func authorizedRequest(url: URL, body: [String: Any]?) throws -> URLRequest {
        var request = URLRequest(url: url)
        if let apiKey, !apiKey.isEmpty {
            switch definition.auth {
            case .bearer: request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            case .xApiKey: request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            case .none: break
            }
        } else if !definition.apiKeyOptional {
            throw AIEngineError(message: "\(definition.name) requires an API key. Add one in Settings.")
        }
        if let body {
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        return request
    }

    private func performRequest(path: String, body: [String: Any]?) async throws -> Data {
        do {
            let url = try resolvedURL(path: path)
            let request = try authorizedRequest(url: url, body: body)
            let (data, response) = try await URLSession.shared.data(for: request)
            try Self.validateHTTPResponse(response, data: data)
            return data
        } catch {
            throw Self.wrapError(error)
        }
    }

    private func performStreamingRequest(path: String, body: [String: Any], onDelta: (String) -> Void) async throws {
        do {
            let url = try resolvedURL(path: path)
            let request = try authorizedRequest(url: url, body: body)
            let (bytes, response) = try await URLSession.shared.bytes(for: request)
            try Self.validateHTTPResponse(response, data: nil)
            for try await line in bytes.lines {
                if let delta = AIOpenAICompletionsWire.parseSSELine(line) {
                    onDelta(delta)
                }
            }
        } catch {
            throw Self.wrapError(error)
        }
    }

    private static func validateHTTPResponse(_ response: URLResponse, data: Data?) throws {
        guard let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) else { return }
        switch http.statusCode {
        case 401, 403:
            throw AIEngineError(message: "Authentication failed — check the API key in Settings.")
        case 429:
            throw AIEngineError(message: "The provider is rate-limiting requests. Try again in a moment.")
        default:
            var message = "The provider returned an error (HTTP \(http.statusCode))."
            if let data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errorObject = json["error"] as? [String: Any], let detail = errorObject["message"] as? String {
                message = detail
            }
            throw AIEngineError(message: message)
        }
    }

    /// Normalizes every failure path (our own validation errors, transport-level `URLError`s,
    /// anything else) into the one `AIEngineError` type `MessageInsightsSession` already knows
    /// how to surface, so no caller outside this file ever has to reason about which of those
    /// kinds of error it's looking at.
    private static func wrapError(_ error: Error) -> AIEngineError {
        if let engineError = error as? AIEngineError { return engineError }
        if error is AITransportPolicy.InsecureEndpointError {
            return AIEngineError(message: "This endpoint must use HTTPS (plain HTTP is only allowed to a local address, like localhost or a LAN server).")
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost, .cannotFindHost, .timedOut, .dnsLookupFailed:
                return AIEngineError(message: "Couldn't reach \(urlError.failingURL?.host ?? "the provider") — check the endpoint and that it's running.")
            default:
                return AIEngineError(message: "A network error occurred: \(urlError.localizedDescription)")
            }
        }
        return AIEngineError(message: "Something went wrong talking to the provider.")
    }
}
