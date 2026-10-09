//
//  Mail Inspector
//
//  Copyright (c) 2026 Nicholas K. Dionysopoulos
//  Licensed under the MIT License. See license.txt in the project root for details.
//

import Foundation

/// One side of a conversation turn, kept generic across every backend (on-device, or a
/// provider's own prior request/response pair for backends that must replay history themselves).
nonisolated enum ChatRole: Sendable {
    case user
    case assistant
}

nonisolated struct ChatTurn: Sendable, Equatable {
    let role: ChatRole
    let text: String
}

/// The outcome of the one structured legitimacy-score call, backend-agnostic. Apple's own
/// `@Generable`-decorated equivalent (`MessageLegitimacyAssessment`) stays private to
/// `OnDeviceAIEngine` — this plain type is what the rest of the app (summary block, PDF export,
/// `MessageInsightsSession`) actually depends on, so none of that code ever needs to know
/// anything requires macOS 27.
nonisolated struct AIScoreResult: Sendable, Equatable {
    let score: Int
    let rationale: String
}

nonisolated struct AIEngineCapabilities: Sendable, Equatable {
    let supportsStreaming: Bool
    let supportsModelListing: Bool
    let requiresApiKey: Bool
    let requiresEndpoint: Bool
}

/// An already-human-readable failure description — each engine is responsible for translating
/// its own backend's errors (a `LanguageModelError`, an HTTP status code, a connection failure)
/// into a short, user-facing string itself, so `MessageInsightsSession` never needs to know which
/// kind of engine produced it.
nonisolated struct AIEngineError: Error, Sendable {
    let message: String
}

/// One configured AI backend for message analysis — today, Apple's on-device model; later,
/// LM Studio, OpenAI, Anthropic, and the rest of the provider catalogue (see the plan at
/// `AIInsights/` for the phased rollout). Deliberately carries no `@available` annotation and no
/// `FoundationModels` dependency: `OnDeviceAIEngine` is the one conformer that needs macOS 27,
/// but nothing that merely holds or calls an `any AIAnalysisEngine` does.
///
/// Each engine instance is stateful and owns exactly one message's conversation for its whole
/// lifetime — constructed once (with its system prompt baked in) and reused for every call. How
/// it remembers prior turns is entirely up to the engine: the on-device engine relies on
/// `LanguageModelSession`'s own transcript; a future HTTP-based engine will maintain its own
/// `[ChatTurn]` array internally and replay it on every request, since those backends are
/// otherwise stateless. `MessageInsightsSession` never manages conversation history itself —
/// that deliberately keeps the "don't let the structured score exchange contaminate later
/// plain-text replies" fix (see `OnDeviceAIEngine`'s doc comment) entirely inside each engine,
/// where the shape of "history" actually differs per backend.
protocol AIAnalysisEngine: AnyObject {
    /// Always a single, historyless call — never part of the ongoing conversation an engine
    /// otherwise maintains. This is what keeps a JSON-shaped structured reply from ever leaking
    /// into later plain-text turns.
    func generateScore(signalsSummary: String) async throws -> AIScoreResult

    /// Continues this engine's own conversation with one more turn. Each yielded `String` is the
    /// *entire* reply accumulated so far, not just the newest fragment — matching
    /// `LanguageModelSession.streamResponse`'s own cumulative-snapshot behavior (confirmed via
    /// `RunCodeSnippet` against the real framework), so every conformer can simply forward or
    /// fold its backend's own increments into that same cumulative contract without the caller
    /// needing to know which kind of increment it originally was.
    func streamRespond(prompt: String) -> AsyncThrowingStream<String, Error>

    var capabilities: AIEngineCapabilities { get }
}
