//
//  Mail Inspector
//
//  Copyright (c) 2026 Nicholas K. Dionysopoulos
//  Licensed under the MIT License. See license.txt in the project root for details.
//

import Foundation

/// Request building and response parsing for the "OpenAI Chat Completions" wire dialect — used
/// by LM Studio, Custom (OpenAI-compatible), and, once added, most of the hosted catalogue. The
/// dialects unique to OpenAI's own Responses API and Anthropic's Messages API are a later phase.
nonisolated enum AIOpenAICompletionsWire {
    static func requestBody(model: String, systemPrompt: String, history: [ChatTurn], newPrompt: String, stream: Bool) -> [String: Any] {
        var messages: [[String: String]] = [["role": "system", "content": systemPrompt]]
        for turn in history {
            messages.append(["role": turn.role == .user ? "user" : "assistant", "content": turn.text])
        }
        messages.append(["role": "user", "content": newPrompt])
        return [
            "model": model,
            "messages": messages,
            "stream": stream,
        ]
    }

    /// Non-streaming response shape: `{"choices":[{"message":{"content": "..."}}]}`, or
    /// `{"error":{"message": "..."}}` on failure.
    static func parseNonStreamingContent(_ data: Data) throws -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AIEngineError(message: "The provider returned a response this app couldn't understand.")
        }
        if let errorObject = json["error"] as? [String: Any], let message = errorObject["message"] as? String {
            throw AIEngineError(message: message)
        }
        guard let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw AIEngineError(message: "The provider's response didn't include any reply text.")
        }
        return content
    }

    /// One line of an SSE stream. Returns the content delta, or `nil` for lines to ignore (blank
    /// lines, the `[DONE]` terminator, or a field this app doesn't surface — including
    /// `reasoning_content`/`reasoning` "thinking" fields some models emit, deliberately dropped
    /// rather than shown, to keep this first pass simple).
    static func parseSSELine(_ line: String) -> String? {
        guard line.hasPrefix("data:") else { return nil }
        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
        guard payload != "[DONE]", !payload.isEmpty else { return nil }
        guard let data = payload.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let delta = first["delta"] as? [String: Any],
              let content = delta["content"] as? String else {
            return nil
        }
        return content
    }

    /// Extracts `{"score": 0-100, "rationale": "..."}` from a model's reply to the score prompt —
    /// the stand-in for Apple's native `@Generable` structured output, which no other provider
    /// has. Tolerates a markdown code fence some models wrap JSON replies in despite being asked
    /// not to, and clamps an out-of-range score rather than failing outright.
    static func parseScoreResult(_ text: String) throws -> AIScoreResult {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("```") {
            if let firstNewline = trimmed.firstIndex(of: "\n") {
                trimmed = String(trimmed[trimmed.index(after: firstNewline)...])
            }
            if let fenceStart = trimmed.range(of: "```", options: .backwards) {
                trimmed = String(trimmed[..<fenceStart.lowerBound])
            }
            trimmed = trimmed.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard let start = trimmed.firstIndex(of: "{"), let end = trimmed.lastIndex(of: "}"), start < end else {
            throw AIEngineError(message: "The provider's response wasn't in the expected format.")
        }
        guard let data = String(trimmed[start...end]).data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let scoreNumber = json["score"] as? NSNumber,
              let rationale = json["rationale"] as? String else {
            throw AIEngineError(message: "The provider's response wasn't in the expected format.")
        }
        let clampedScore = max(0, min(100, scoreNumber.intValue))
        return AIScoreResult(score: clampedScore, rationale: rationale)
    }
}
