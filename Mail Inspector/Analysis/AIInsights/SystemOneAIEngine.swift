//
//  Mail Inspector
//
//  Copyright (c) 2026 Nicholas K. Dionysopoulos / Akeeba Ltd
//  Licensed under the MIT License. See license.txt in the project root for details.
//

import Foundation

/// An `AIAnalysisEngine` for TypeSafe.ai's System One API ("Jev"), or any self-hosted/alternative
/// service that speaks the same `noul`-question shape (e.g. Laya, Clef — see
/// `.claude/docs/system-one-jev.md`). Unlike `RemoteAIEngine`, this is a single stateless POST per
/// message: no chat history, no streaming, no model listing — `generateScore` is the entire
/// engine. `capabilities.supportsChat` is false, which is what keeps `MessageInsightsSession` from
/// ever calling `streamRespond` on this engine in practice.
@MainActor
final class SystemOneAIEngine: AIAnalysisEngine {
    private let definition: AIProviderDefinition
    private let endpoint: String
    private let apiKey: String?
    private let prompt: String
    /// `nil`/0 for Jev itself (fixed hosted endpoint, no context-window knob to set); a positive
    /// value only ever comes from the editable-endpoint ("System One compatible") provider.
    private let contextLength: Int?

    init(definition: AIProviderDefinition, endpoint: String, apiKey: String?, prompt: String, contextLength: Int?) {
        guard case .systemOne = definition.kind else {
            fatalError("SystemOneAIEngine constructed with a non-systemOne provider definition: \(definition.key)")
        }
        self.definition = definition
        self.endpoint = endpoint
        self.apiKey = apiKey
        self.prompt = prompt
        self.contextLength = contextLength
    }

    /// The tested, shipped-with-the-app `noul` question. Optimized for TypeSafe.ai's own Jev
    /// model — a self-hosted/alternative System One-compatible service may need a different
    /// phrasing to yield comparably well-separated scores. Editable per-provider in Settings via
    /// `InspectorSettings.aiProviderPrompts`, and resettable back to this constant.
    ///
    /// Explicitly calls out the `[notable]`/`[info]`/`[warning]` severity tags
    /// `EmailSignalsSummary` puts on every delivery-path/sender-identity line — without that,
    /// live testing (2026-10-09) showed Jev scoring ordinary mail pessimistically, because routine,
    /// deliberately-low-severity flags (e.g. a message relayed through a sender's own SaaS
    /// infrastructure, tagged `[notable]` precisely because it's harmless — see
    /// `DeliveryPathAnalyzer`) still read as "an anomaly" once lumped in with genuine `[warning]`s.
    static let defaultPrompt = """
        Is this email a legitimate message genuinely sent by the sender it claims to be from, \
        rather than a forged, spoofed, or phishing attempt? Base your judgment only on the \
        signal digest provided above. Weigh the SPF/DKIM/DMARC results and alignment most \
        heavily. Delivery-path and sender-identity lines tagged [notable] or [info] describe \
        routine, usually-harmless patterns (such as a message relayed through the sender's own \
        infrastructure) and should NOT by themselves count against legitimacy — only \
        [warning]-tagged lines, failing/misaligned authentication, or a high spam-filter score \
        should.
        """

    var capabilities: AIEngineCapabilities {
        AIEngineCapabilities(
            supportsStreaming: false,
            supportsModelListing: false,
            requiresApiKey: !definition.apiKeyOptional,
            requiresEndpoint: definition.isEndpointEditable,
            supportsChat: false
        )
    }

    func generateScore(signalsSummary: String) async throws -> AIScoreResult {
        let body = AISystemOneWire.requestBody(prompt: prompt, signalsSummary: signalsSummary, contextLength: contextLength)
        let data = try await performRequest(body: body)
        let score = try AISystemOneWire.parseScore(data)
        return AIScoreResult(score: score, rationale: "\(definition.name) returns a legitimacy score only — no rationale, further analysis, or chat is available.")
    }

    /// Never actually called — `capabilities.supportsChat` is false, so `MessageInsightsSession`
    /// never invokes this. Throws rather than silently yielding nothing, in case that assumption
    /// ever stops holding.
    func streamRespond(prompt: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: AIEngineError(message: "\(definition.name) doesn't support chat — it only returns a legitimacy score."))
        }
    }

    // MARK: - HTTP plumbing

    private func performRequest(body: [String: Any]) async throws -> Data {
        do {
            guard let url = URL(string: endpoint) else {
                throw AIEngineError(message: "The configured endpoint isn't a valid URL.")
            }
            try AITransportPolicy.validate(url)

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            if let apiKey, !apiKey.isEmpty {
                request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            } else if !definition.apiKeyOptional {
                throw AIEngineError(message: "\(definition.name) requires an API key. Add one in Settings.")
            }
            request.httpBody = try JSONSerialization.data(withJSONObject: body)

            let (data, response) = try await URLSession.shared.data(for: request)
            try Self.validateHTTPResponse(response, data: data)
            return data
        } catch {
            throw Self.wrapError(error)
        }
    }

    private static func validateHTTPResponse(_ response: URLResponse, data: Data?) throws {
        guard let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) else { return }
        switch http.statusCode {
        case 401, 403:
            throw AIEngineError(message: "Authentication failed — check the API key in Settings.")
        case 422:
            throw AIEngineError(message: "The provider rejected the request as invalid.")
        case 429:
            throw AIEngineError(message: "The provider is rate-limiting requests. Try again in a moment.")
        case 529:
            throw AIEngineError(message: "The provider is temporarily overloaded. Try again in a moment.")
        default:
            var message = "The provider returned an error (HTTP \(http.statusCode))."
            if let data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errorObject = json["error"] as? [String: Any], let detail = errorObject["message"] as? String {
                message = detail
            }
            throw AIEngineError(message: message)
        }
    }

    /// Mirrors `RemoteAIEngine.wrapError` — normalizes every failure path into the one
    /// `AIEngineError` type `MessageInsightsSession` already knows how to surface.
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
