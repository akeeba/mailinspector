//
//  Mail Inspector
//
//  Copyright (c) 2026 Nicholas K. Dionysopoulos / Akeeba Ltd
//  Licensed under the MIT License. See license.txt in the project root for details.
//

import Testing
import Foundation
@testable import Mail_Inspector

/// Tests for `AIOpenAIResponsesWire`: OpenAI's own Responses API shape, distinct from the Chat
/// Completions dialect every other provider (including Custom/LM Studio) speaks.
@Suite("AIOpenAIResponsesWire")
struct AIOpenAIResponsesWireTests {
    @Test("Builds a request body with instructions and input turns in order, no conversation chaining")
    func buildsRequestBodyInOrder() throws {
        let history = [ChatTurn(role: .user, text: "Hi"), ChatTurn(role: .assistant, text: "Hello")]
        let body = AIOpenAIResponsesWire.requestBody(model: "test-model", systemPrompt: "Be helpful.", history: history, newPrompt: "What now?", stream: true)

        #expect(body["model"] as? String == "test-model")
        #expect(body["instructions"] as? String == "Be helpful.")
        #expect(body["stream"] as? Bool == true)
        #expect(body["previous_response_id"] == nil)
        let input = try #require(body["input"] as? [[String: String]])
        #expect(input.count == 3)
        #expect(input[0] == ["role": "user", "content": "Hi"])
        #expect(input[1] == ["role": "assistant", "content": "Hello"])
        #expect(input[2] == ["role": "user", "content": "What now?"])
    }

    @Test("Parses the non-streaming reply text out of output[].content[].text")
    func parsesNonStreamingContent() throws {
        let json = #"{"output":[{"type":"message","content":[{"type":"output_text","text":"Hello there."}]}]}"#
        let text = try AIOpenAIResponsesWire.parseNonStreamingContent(Data(json.utf8))
        #expect(text == "Hello there.")
    }

    @Test("Throws using the provider's own error message when the response is an error object")
    func throwsProviderErrorMessage() throws {
        let json = #"{"error":{"message":"Invalid API key"}}"#
        #expect {
            try AIOpenAIResponsesWire.parseNonStreamingContent(Data(json.utf8))
        } throws: { error in
            (error as? AIEngineError)?.message == "Invalid API key"
        }
    }

    @Test("Extracts a content delta from a response.output_text.delta event")
    func parsesOutputTextDelta() throws {
        let line = #"data: {"type":"response.output_text.delta","delta":"Hel"}"#
        #expect(AIOpenAIResponsesWire.parseSSELine(line) == "Hel")
    }

    @Test("Ignores other event types, like response.created or response.completed")
    func ignoresOtherEventTypes() throws {
        #expect(AIOpenAIResponsesWire.parseSSELine(#"data: {"type":"response.created"}"#) == nil)
        #expect(AIOpenAIResponsesWire.parseSSELine(#"data: {"type":"response.completed"}"#) == nil)
    }

    @Test("Ignores a line that isn't an SSE data line at all")
    func ignoresNonDataLine() throws {
        #expect(AIOpenAIResponsesWire.parseSSELine("") == nil)
        #expect(AIOpenAIResponsesWire.parseSSELine("event: response.output_text.delta") == nil)
    }
}
