//
//  Mail Inspector
//
//  Copyright (c) 2026 Nicholas K. Dionysopoulos
//  Licensed under the MIT License. See license.txt in the project root for details.
//

import Foundation

/// Request building and response parsing for Anthropic's Messages API. Unlike the OpenAI-style
/// dialects, the system prompt is its own top-level `system` field, not a message, and
/// `max_tokens` is a required field with no server-side default — this app always sends a fixed
/// value rather than exposing it as another setting.
nonisolated enum AIAnthropicWire: AIWireDialectHandler {
    private static let maxTokens = 1024

    static func requestBody(model: String, systemPrompt: String, history: [ChatTurn], newPrompt: String, stream: Bool) -> [String: Any] {
        var messages: [[String: String]] = []
        for turn in history {
            messages.append(["role": turn.role == .user ? "user" : "assistant", "content": turn.text])
        }
        messages.append(["role": "user", "content": newPrompt])
        return [
            "model": model,
            "system": systemPrompt,
            "messages": messages,
            "max_tokens": maxTokens,
            "stream": stream,
        ]
    }

    /// Non-streaming response shape: `{"content":[{"type":"text","text":"..."}]}`, or
    /// `{"error":{"message":"..."}}` on failure (actually `{"type":"error","error":{...}}`, but
    /// the inner shape is the same `{"message": "..."}` this app already expects).
    static func parseNonStreamingContent(_ data: Data) throws -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AIEngineError(message: "The provider returned a response this app couldn't understand.")
        }
        if let errorObject = json["error"] as? [String: Any], let message = errorObject["message"] as? String {
            throw AIEngineError(message: message)
        }
        guard let content = json["content"] as? [[String: Any]],
              let first = content.first(where: { $0["type"] as? String == "text" }),
              let text = first["text"] as? String else {
            throw AIEngineError(message: "The provider's response didn't include any reply text.")
        }
        return text
    }

    /// One line of an SSE stream. Only a `content_block_delta` event whose own delta is a
    /// `text_delta` carries visible reply text — `thinking_delta` (extended-thinking models) is
    /// deliberately ignored, same as the "reasoning" fields the other dialects drop.
    static func parseSSELine(_ line: String) -> String? {
        guard line.hasPrefix("data:") else { return nil }
        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
        guard !payload.isEmpty,
              let data = payload.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              json["type"] as? String == "content_block_delta",
              let delta = json["delta"] as? [String: Any],
              delta["type"] as? String == "text_delta",
              let text = delta["text"] as? String else {
            return nil
        }
        return text
    }
}
