//
//  Mail Inspector
//
//  Copyright (c) 2026 Nicholas K. Dionysopoulos
//  Licensed under the MIT License. See license.txt in the project root for details.
//

import Foundation

/// Request building and response parsing for OpenAI's own Responses API — distinct from the
/// Chat Completions shape (`AIOpenAICompletionsWire`) that most other providers, including
/// Custom/LM Studio, actually speak. This app doesn't use any of the Responses API's own
/// conversation-chaining (`previous_response_id`) — each request simply replays the full history
/// as `input` turns, the same way every other dialect does, since `RemoteAIEngine` already owns
/// that history itself.
nonisolated enum AIOpenAIResponsesWire: AIWireDialectHandler {
    static func requestBody(model: String, systemPrompt: String, history: [ChatTurn], newPrompt: String, stream: Bool) -> [String: Any] {
        var input: [[String: String]] = []
        for turn in history {
            input.append(["role": turn.role == .user ? "user" : "assistant", "content": turn.text])
        }
        input.append(["role": "user", "content": newPrompt])
        return [
            "model": model,
            "instructions": systemPrompt,
            "input": input,
            "stream": stream,
        ]
    }

    /// Non-streaming response shape: `{"output":[{"type":"message","content":[{"type":
    /// "output_text","text":"..."}]}]}`, or `{"error":{"message":"..."}}` on failure.
    static func parseNonStreamingContent(_ data: Data) throws -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AIEngineError(message: "The provider returned a response this app couldn't understand.")
        }
        if let errorObject = json["error"] as? [String: Any], let message = errorObject["message"] as? String {
            throw AIEngineError(message: message)
        }
        guard let output = json["output"] as? [[String: Any]] else {
            throw AIEngineError(message: "The provider's response didn't include any reply text.")
        }
        let text = output
            .filter { $0["type"] as? String == "message" }
            .compactMap { $0["content"] as? [[String: Any]] }
            .flatMap { $0 }
            .filter { $0["type"] as? String == "output_text" }
            .compactMap { $0["text"] as? String }
            .joined()
        guard !text.isEmpty else {
            throw AIEngineError(message: "The provider's response didn't include any reply text.")
        }
        return text
    }

    /// One line of an SSE stream. Only `response.output_text.delta` events carry visible reply
    /// text; `response.created`/`response.completed`/reasoning-summary events are ignored.
    static func parseSSELine(_ line: String) -> String? {
        guard line.hasPrefix("data:") else { return nil }
        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
        guard !payload.isEmpty,
              let data = payload.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              json["type"] as? String == "response.output_text.delta",
              let delta = json["delta"] as? String else {
            return nil
        }
        return delta
    }
}
