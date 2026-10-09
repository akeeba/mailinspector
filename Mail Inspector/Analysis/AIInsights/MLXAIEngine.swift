//
//  Mail Inspector
//
//  Copyright (c) 2026 Nicholas K. Dionysopoulos / Akeeba Ltd
//  Licensed under the MIT License. See license.txt in the project root for details.
//

import Foundation
import MLXLLM
import MLXLMCommon
import Tokenizers

/// Bridges a `swift-transformers` `Tokenizer` into `mlx-swift-lm`'s own `Tokenizer` protocol.
/// Despite the identical name, these are two distinct, differently-shaped protocols — `mlx-swift-lm`
/// 3.x ships no tokenizer implementation of its own, only the `TokenizerLoader` extension point,
/// same gap the proven Grafida integration hit (its `GrafidaTokenizerLoader.swift`) — so this
/// can't just be a type alias or a plain upcast. `Message`/`ToolSpec` on the `swift-transformers`
/// side are themselves just type aliases for `[String: any Sendable]`, identical to what
/// `MLXLMCommon.Tokenizer.applyChatTemplate` expects, so `additionalContext` (and with it,
/// `LocalModelDescriptor.chatTemplateContext`) passes straight through unchanged.
private struct MLXTokenizerBridge: MLXLMCommon.Tokenizer {
    let wrapped: any Tokenizers.Tokenizer

    func encode(text: String, addSpecialTokens: Bool) -> [Int] {
        wrapped.encode(text: text, addSpecialTokens: addSpecialTokens)
    }

    func decode(tokenIds: [Int], skipSpecialTokens: Bool) -> String {
        wrapped.decode(tokens: tokenIds, skipSpecialTokens: skipSpecialTokens)
    }

    func convertTokenToId(_ token: String) -> Int? {
        wrapped.convertTokenToId(token)
    }

    func convertIdToToken(_ id: Int) -> String? {
        wrapped.convertIdToToken(id)
    }

    var bosToken: String? { wrapped.bosToken }
    var eosToken: String? { wrapped.eosToken }
    var unknownToken: String? { wrapped.unknownToken }

    func applyChatTemplate(
        messages: [[String: any Sendable]],
        tools: [[String: any Sendable]]?,
        additionalContext: [String: any Sendable]?
    ) throws -> [Int] {
        try wrapped.applyChatTemplate(messages: messages, tools: tools, additionalContext: additionalContext)
    }
}

/// Loads a tokenizer from the model's own local directory via `swift-transformers`'s
/// `AutoTokenizer`. `hubApi` is passed its default and is documented by `swift-transformers`
/// itself as "unused for local loading", so this never touches the network — everything needed
/// already exists in `directory`.
private struct LocalFolderTokenizerLoader: TokenizerLoader {
    func load(from directory: URL) async throws -> any MLXLMCommon.Tokenizer {
        let tokenizer = try await AutoTokenizer.from(modelFolder: directory)
        return MLXTokenizerBridge(wrapped: tokenizer)
    }
}

/// Holds at most one loaded MLX model at a time, evicting the previous one before loading a
/// different model — reloading multi-gigabyte weights on every message would be both slow and,
/// per Grafida's own hard-won experience, a real jetsam-crash risk if two stayed resident at
/// once. An actor so concurrent calls for the same model key naturally serialize onto the same
/// in-flight load rather than racing to load it twice.
private actor MLXModelContainerCache {
    static let shared = MLXModelContainerCache()

    private var cached: (key: String, container: ModelContainer)?

    func container(for descriptor: LocalModelDescriptor, at directory: URL) async throws -> ModelContainer {
        if let cached, cached.key == descriptor.key {
            return cached.container
        }
        let container = try await LLMModelFactory.shared.loadContainer(
            from: directory,
            using: LocalFolderTokenizerLoader()
        )
        cached = (descriptor.key, container)
        return container
    }
}

/// An on-device MLX model, wrapped as an `AIAnalysisEngine`. Only ever constructed by
/// `AIEngineFactory` once `LocalModelSuitability` and `LocalModelStore.isInstalled` have both
/// already said yes — this type assumes the model is present on disk and the Mac can run it.
///
/// No JSON-schema-constrained decoding is available here (`mlx-swift-lm` deliberately excludes
/// grammar-constrained generation for licensing reasons — see `.claude/docs/on-device-mlx-llm.md`),
/// so the score call is prompt-and-parse via `AIScoreJSONParser`, exactly like `RemoteAIEngine`,
/// not the `@Generable`-constrained approach `OnDeviceAIEngine` gets from Apple's framework.
///
/// Uses a throwaway `ChatSession` for the single structured-score call and a separate, long-lived
/// one for chat, deliberately never the same session for both — the same isolation
/// `OnDeviceAIEngine` and `RemoteAIEngine` already use, and for the same reason: letting a
/// structured JSON exchange sit in a transcript a model will later continue in plain text risks
/// it imitating that JSON shape in later replies.
@MainActor
final class MLXAIEngine: AIAnalysisEngine {
    private let descriptor: LocalModelDescriptor
    private let systemPrompt: String
    private var chatSession: ChatSession?

    /// Pinned low for the score call specifically: hands-on JSON-schema testing (see
    /// `.claude/docs/on-device-mlx-llm.md`) found both candidate models became markedly less
    /// reliable at distinguishing an obvious phishing attempt from a legitimate message at
    /// higher sampling temperatures, even though schema adherence itself stayed intact.
    private static let scoreTemperature: Float = 0.2
    private static let scoreMaxTokens = 400

    init(descriptor: LocalModelDescriptor, systemPrompt: String) {
        self.descriptor = descriptor
        self.systemPrompt = systemPrompt
    }

    var capabilities: AIEngineCapabilities {
        AIEngineCapabilities(
            supportsStreaming: true,
            supportsModelListing: false,
            requiresApiKey: false,
            requiresEndpoint: false,
            supportsChat: true
        )
    }

    func generateScore(signalsSummary: String) async throws -> AIScoreResult {
        do {
            let container = try await loadedContainer()
            let prompt = """
                Here is the computed signal digest for this email:

                \(signalsSummary)

                Assess how legitimate this message is. Respond with ONLY a single JSON object of the \
                exact shape {"score": <integer 0-100>, "rationale": "<one or two sentence rationale>"} \
                and nothing else — no markdown code fence, no extra commentary, no other text.
                """
            // A throwaway session, deliberately never reused for chat — see the type-level
            // comment for why.
            let scoringSession = ChatSession(
                container,
                instructions: systemPrompt,
                generateParameters: GenerateParameters(maxTokens: Self.scoreMaxTokens, temperature: Self.scoreTemperature),
                additionalContext: descriptor.chatTemplateContext
            )
            let text = try await scoringSession.respond(to: prompt)
            return try AIScoreJSONParser.parse(text)
        } catch {
            throw Self.wrapError(error)
        }
    }

    func streamRespond(prompt: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let session = try await chatSessionForConversation()
                    // `ChatSession.streamResponse` yields incremental deltas, not cumulative
                    // snapshots — the opposite of `LanguageModelSession`'s behavior. Folding
                    // them into a running total here is what keeps `AIAnalysisEngine`'s
                    // cumulative contract true for every conformer regardless of which kind of
                    // increment its backend actually produces.
                    var accumulated = ""
                    for try await delta in session.streamResponse(to: prompt) {
                        try Task.checkCancellation()
                        accumulated += delta
                        continuation.yield(accumulated)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: Self.wrapError(error))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func loadedContainer() async throws -> ModelContainer {
        let directory = LocalModelStore.shared.installDirectory(for: descriptor)
        return try await MLXModelContainerCache.shared.container(for: descriptor, at: directory)
    }

    private func chatSessionForConversation() async throws -> ChatSession {
        if let chatSession { return chatSession }
        let container = try await loadedContainer()
        let session = ChatSession(
            container,
            instructions: systemPrompt,
            additionalContext: descriptor.chatTemplateContext
        )
        chatSession = session
        return session
    }

    private static func wrapError(_ error: Error) -> AIEngineError {
        if let engineError = error as? AIEngineError { return engineError }
        if error is CancellationError { return AIEngineError(message: "Cancelled.") }
        return AIEngineError(message: "Something went wrong running \(error)")
    }
}
