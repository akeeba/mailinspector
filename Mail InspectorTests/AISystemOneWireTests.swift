//
//  Mail Inspector
//
//  Copyright (c) 2026 Nicholas K. Dionysopoulos / Akeeba Ltd
//  Licensed under the MIT License. See license.txt in the project root for details.
//

import Testing
import Foundation
@testable import Mail_Inspector

/// Tests for `AISystemOneWire`: building a TypeSafe.ai System One (`noul` question) request body,
/// and parsing its `{"answers": {"<key>": {"noul": <0-1>}}}` reply into a 0-100 score.
@Suite("AISystemOneWire")
struct AISystemOneWireTests {
    @Test("Builds a request body with the state, a fixed model, and the noul question/instructions")
    func buildsRequestBodyWithoutContextLength() throws {
        let body = AISystemOneWire.requestBody(prompt: "Is this legit?", signalsSummary: "SPF: pass", contextLength: nil)

        #expect(body["state"] as? String == "SPF: pass")
        #expect(body["model"] as? String == "jev-latest")
        let questions = try #require(body["questions"] as? [String: Any])
        let question = try #require(questions[AISystemOneWire.questionKey] as? [String: Any])
        #expect(question["type"] as? String == "noul")
        #expect(question["instructions"] as? String == "Is this legit?")
        #expect(body["context_length"] == nil)
    }

    @Test("Omits context_length when nil or zero, includes it when positive")
    func contextLengthInclusionRules() throws {
        let withNil = AISystemOneWire.requestBody(prompt: "p", signalsSummary: "s", contextLength: nil)
        #expect(withNil["context_length"] == nil)

        let withZero = AISystemOneWire.requestBody(prompt: "p", signalsSummary: "s", contextLength: 0)
        #expect(withZero["context_length"] == nil)

        let withPositive = AISystemOneWire.requestBody(prompt: "p", signalsSummary: "s", contextLength: 8192)
        #expect(withPositive["context_length"] as? Int == 8192)
    }

    @Test("Parses a noul float, rescaled to a 0-100 integer score")
    func parsesNoulScore() throws {
        let json = #"{"answers":{"\#(AISystemOneWire.questionKey)":{"type":"noul","noul":0.93}}}"#
        #expect(try AISystemOneWire.parseScore(Data(json.utf8)) == 93)
    }

    @Test("Rounds and clamps edge-case noul values into 0...100")
    func roundsAndClampsEdgeCases() throws {
        func score(_ noul: Double) throws -> Int {
            let json = #"{"answers":{"\#(AISystemOneWire.questionKey)":{"type":"noul","noul":\#(noul)}}}"#
            return try AISystemOneWire.parseScore(Data(json.utf8))
        }
        #expect(try score(0.0) == 0)
        #expect(try score(1.0) == 100)
        #expect(try score(1.5) == 100)
        #expect(try score(-0.5) == 0)
        #expect(try score(0.125) == 13)
    }

    @Test("Throws using the provider's own error message when the response is an error object")
    func throwsProviderErrorMessage() throws {
        let json = #"{"error":{"message":"Missing or invalid API key"}}"#
        #expect {
            try AISystemOneWire.parseScore(Data(json.utf8))
        } throws: { error in
            (error as? AIEngineError)?.message == "Missing or invalid API key"
        }
    }

    @Test("Throws a clear error when the answer for the expected question key is missing")
    func throwsOnMissingAnswer() throws {
        let json = #"{"answers":{"some_other_question":{"type":"noul","noul":0.5}}}"#
        #expect(throws: AIEngineError.self) {
            try AISystemOneWire.parseScore(Data(json.utf8))
        }
    }
}
