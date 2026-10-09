//
//  Mail Inspector
//
//  Copyright (c) 2026 Nicholas K. Dionysopoulos
//  Licensed under the MIT License. See license.txt in the project root for details.
//

import Testing
import Foundation
@testable import Mail_Inspector

/// Tests for `AIOpenAICompletionsWire`: building an OpenAI-Chat-Completions-shaped request body
/// (used by LM Studio, Custom, and most of the hosted provider catalogue) and parsing both
/// streaming (SSE) and non-streaming replies. Score-JSON extraction is shared across every
/// dialect — see `AIScoreJSONParserTests`.
@Suite("AIOpenAICompletionsWire")
struct AIOpenAICompletionsWireTests {
    @Test("Builds a request body with the system prompt, prior history, and the new prompt in order")
    func buildsRequestBodyInOrder() throws {
        let history = [ChatTurn(role: .user, text: "Hi"), ChatTurn(role: .assistant, text: "Hello")]
        let body = AIOpenAICompletionsWire.requestBody(model: "test-model", systemPrompt: "Be helpful.", history: history, newPrompt: "What now?", stream: true)

        #expect(body["model"] as? String == "test-model")
        #expect(body["stream"] as? Bool == true)
        let messages = try #require(body["messages"] as? [[String: String]])
        #expect(messages.count == 4)
        #expect(messages[0] == ["role": "system", "content": "Be helpful."])
        #expect(messages[1] == ["role": "user", "content": "Hi"])
        #expect(messages[2] == ["role": "assistant", "content": "Hello"])
        #expect(messages[3] == ["role": "user", "content": "What now?"])
    }

    @Test("Parses the non-streaming reply text out of a choices[0].message.content response")
    func parsesNonStreamingContent() throws {
        let json = #"{"choices":[{"message":{"role":"assistant","content":"Hello there."}}]}"#
        let text = try AIOpenAICompletionsWire.parseNonStreamingContent(Data(json.utf8))
        #expect(text == "Hello there.")
    }

    @Test("Throws using the provider's own error message when the response is an error object")
    func throwsProviderErrorMessage() throws {
        let json = #"{"error":{"message":"Invalid API key"}}"#
        #expect {
            try AIOpenAICompletionsWire.parseNonStreamingContent(Data(json.utf8))
        } throws: { error in
            (error as? AIEngineError)?.message == "Invalid API key"
        }
    }

    @Test("Extracts a content delta from a well-formed SSE data line")
    func parsesSSELineDelta() throws {
        let line = #"data: {"choices":[{"delta":{"content":"Hel"}}]}"#
        #expect(AIOpenAICompletionsWire.parseSSELine(line) == "Hel")
    }

    @Test("Ignores the [DONE] terminator line")
    func ignoresDoneLine() throws {
        #expect(AIOpenAICompletionsWire.parseSSELine("data: [DONE]") == nil)
    }

    @Test("Ignores a line with no content delta (e.g. a role-only opening chunk)")
    func ignoresLineWithoutContent() throws {
        let line = #"data: {"choices":[{"delta":{"role":"assistant"}}]}"#
        #expect(AIOpenAICompletionsWire.parseSSELine(line) == nil)
    }

    @Test("Ignores a line that isn't an SSE data line at all")
    func ignoresNonDataLine() throws {
        #expect(AIOpenAICompletionsWire.parseSSELine("") == nil)
        #expect(AIOpenAICompletionsWire.parseSSELine("event: ping") == nil)
    }
}
