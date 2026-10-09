//
//  Mail Inspector
//
//  Copyright (c) 2026 Nicholas K. Dionysopoulos
//  Licensed under the MIT License. See license.txt in the project root for details.
//

import Testing
import Foundation
@testable import Mail_Inspector

/// Tests for `AIScoreJSONParser`: extracting `{"score", "rationale"}` from a remote model's
/// plain-text reply, shared across every wire dialect — the stand-in for Apple's native
/// `@Generable` structured output, which no other provider has.
@Suite("AIScoreJSONParser")
struct AIScoreJSONParserTests {
    @Test("Extracts score and rationale from a clean JSON reply")
    func parsesCleanScoreJSON() throws {
        let result = try AIScoreJSONParser.parse(#"{"score": 42, "rationale": "Mixed signals."}"#)
        #expect(result.score == 42)
        #expect(result.rationale == "Mixed signals.")
    }

    @Test("Strips a markdown code fence some models wrap the JSON reply in despite being told not to")
    func stripsMarkdownFence() throws {
        let fenced = "```json\n{\"score\": 10, \"rationale\": \"Looks forged.\"}\n```"
        let result = try AIScoreJSONParser.parse(fenced)
        #expect(result.score == 10)
        #expect(result.rationale == "Looks forged.")
    }

    @Test("Clamps an out-of-range score into 0...100 rather than failing")
    func clampsOutOfRangeScore() throws {
        let result = try AIScoreJSONParser.parse(#"{"score": 150, "rationale": "Overconfident."}"#)
        #expect(result.score == 100)
    }

    @Test("Throws a clear error when the reply has no JSON object in it at all")
    func throwsOnMissingJSON() throws {
        #expect(throws: AIEngineError.self) {
            try AIScoreJSONParser.parse("I'm not sure how to answer that.")
        }
    }
}
