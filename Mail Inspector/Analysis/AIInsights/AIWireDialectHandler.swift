//
//  Mail Inspector
//
//  Copyright (c) 2026 Nicholas K. Dionysopoulos
//  Licensed under the MIT License. See license.txt in the project root for details.
//

import Foundation

/// The shared shape every wire dialect (`AIOpenAICompletionsWire`, `AIOpenAIResponsesWire`,
/// `AIAnthropicWire`) implements, so `RemoteAIEngine` can hold one dialect's type and call it
/// uniformly regardless of which provider it's actually talking to. Score-JSON extraction isn't
/// part of this — see `AIScoreJSONParser` — since asking for (and parsing) a `{"score",
/// "rationale"}` reply is this app's own convention layered on top of every dialect alike, not
/// something that varies by wire format.
protocol AIWireDialectHandler {
    // Every requirement is explicitly `nonisolated`: without it, the project's
    // `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` setting makes the *protocol's* requirements
    // implicitly MainActor-isolated, which then forces conforming witnesses to match that
    // isolation even though each conforming type here is declared `nonisolated enum` — these are
    // pure parsing functions with no actor affinity at all, and callers (tests included) need to
    // reach them from a plain synchronous, non-isolated context.
    nonisolated static func requestBody(model: String, systemPrompt: String, history: [ChatTurn], newPrompt: String, stream: Bool) -> [String: Any]

    /// Parses a complete, non-streaming response body into the reply text, or throws an
    /// `AIEngineError` using the provider's own error message when the body is an error shape.
    nonisolated static func parseNonStreamingContent(_ data: Data) throws -> String

    /// One line of an SSE stream. Returns the content delta for that line, or `nil` for lines to
    /// ignore (blank lines, `event:` lines, a terminator, or any field this app doesn't surface).
    nonisolated static func parseSSELine(_ line: String) -> String?
}
