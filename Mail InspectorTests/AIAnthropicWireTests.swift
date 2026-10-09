//
//  Mail Inspector
//
//  Copyright (c) 2026 Nicholas K. Dionysopoulos
//  Licensed under the MIT License. See license.txt in the project root for details.
//

import Testing
import Foundation
@testable import Mail_Inspector

/// Tests for `AIAnthropicWire`: Anthropic's Messages API shape, where the system prompt is its
/// own top-level field (not a message) and `max_tokens` is always sent (Anthropic requires it,
/// with no server-side default).
@Suite("AIAnthropicWire")
struct AIAnthropicWireTests {
    @Test("Builds a request body with the system prompt as its own field, not a message, plus a required max_tokens")
    func buildsRequestBodyWithTopLevelSystemPrompt() throws {
        let history = [ChatTurn(role: .user, text: "Hi"), ChatTurn(role: .assistant, text: "Hello")]
        let body = AIAnthropicWire.requestBody(model: "test-model", systemPrompt: "Be helpful.", history: history, newPrompt: "What now?", stream: true)

        #expect(body["model"] as? String == "test-model")
        #expect(body["system"] as? String == "Be helpful.")
        #expect(body["stream"] as? Bool == true)
        #expect((body["max_tokens"] as? Int ?? 0) > 0)
        let messages = try #require(body["messages"] as? [[String: String]])
        #expect(messages.count == 3)
        #expect(messages[0] == ["role": "user", "content": "Hi"])
        #expect(messages[1] == ["role": "assistant", "content": "Hello"])
        #expect(messages[2] == ["role": "user", "content": "What now?"])
    }

    @Test("Parses the non-streaming reply text out of content[] where type is text")
    func parsesNonStreamingContent() throws {
        let json = #"{"content":[{"type":"text","text":"Hello there."}]}"#
        let text = try AIAnthropicWire.parseNonStreamingContent(Data(json.utf8))
        #expect(text == "Hello there.")
    }

    @Test("Throws using the provider's own error message when the response is an error object")
    func throwsProviderErrorMessage() throws {
        let json = #"{"type":"error","error":{"type":"authentication_error","message":"Invalid API key"}}"#
        #expect {
            try AIAnthropicWire.parseNonStreamingContent(Data(json.utf8))
        } throws: { error in
            (error as? AIEngineError)?.message == "Invalid API key"
        }
    }

    @Test("Extracts a content delta from a content_block_delta text_delta event")
    func parsesTextDelta() throws {
        let line = #"data: {"type":"content_block_delta","delta":{"type":"text_delta","text":"Hel"}}"#
        #expect(AIAnthropicWire.parseSSELine(line) == "Hel")
    }

    @Test("Ignores a thinking_delta event (extended-thinking models), same as other dialects drop reasoning fields")
    func ignoresThinkingDelta() throws {
        let line = #"data: {"type":"content_block_delta","delta":{"type":"thinking_delta","thinking":"Let me consider..."}}"#
        #expect(AIAnthropicWire.parseSSELine(line) == nil)
    }

    @Test("Ignores other event types, like message_start or message_stop")
    func ignoresOtherEventTypes() throws {
        #expect(AIAnthropicWire.parseSSELine(#"data: {"type":"message_start"}"#) == nil)
        #expect(AIAnthropicWire.parseSSELine(#"data: {"type":"message_stop"}"#) == nil)
    }

    @Test("Ignores a line that isn't an SSE data line at all")
    func ignoresNonDataLine() throws {
        #expect(AIAnthropicWire.parseSSELine("") == nil)
        #expect(AIAnthropicWire.parseSSELine("event: content_block_delta") == nil)
    }
}
