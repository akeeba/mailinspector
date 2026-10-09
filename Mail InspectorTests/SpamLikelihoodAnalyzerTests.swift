//
//  Mail Inspector
//
//  Copyright (c) 2026 Nicholas K. Dionysopoulos / Akeeba Ltd
//  Licensed under the MIT License. See license.txt in the project root for details.
//

import Testing
import Foundation
@testable import Mail_Inspector

/// Tests for `SpamLikelihoodAnalyzer`: rescaling various mail-filter spam-scoring headers
/// (X-Spam-Score, X-Spam-Status, Exchange SCL, Rspamd, X-MBO-SPAM-Probability) onto a common
/// 0-100 gauge, falling through to the next recognized source when one is blank, and returning
/// nil when no recognized header is present at all.
@Suite("SpamLikelihoodAnalyzer")
struct SpamLikelihoodAnalyzerTests {
    @Test("Rescales an X-Spam-Score onto a 0-100 gauge")
    func rescalesSpamScore() throws {
        let message = try makeTestMessage("X-Spam-Score: 5.0\r\n\r\n")
        let assessment = SpamLikelihoodAnalyzer.assess(parsed: message.parsed)
        #expect(assessment?.sourceHeaderName == "X-Spam-Score")
        #expect(assessment?.percentage == 50)
    }

    @Test("Extracts the score from an X-Spam-Status line when X-Spam-Score is absent")
    func extractsScoreFromStatusLine() throws {
        let message = try makeTestMessage("X-Spam-Status: No, score=-2.3 required=5.0 tests=NONE\r\n\r\n")
        let assessment = SpamLikelihoodAnalyzer.assess(parsed: message.parsed)
        #expect(assessment?.sourceHeaderName == "X-Spam-Status")
        #expect(assessment?.percentage == 13.5)
    }

    @Test("Rescales Exchange's Spam Confidence Level onto a 0-100 gauge")
    func rescalesSCL() throws {
        let message = try makeTestMessage("X-MS-Exchange-Organization-SCL: 9\r\n\r\n")
        let assessment = SpamLikelihoodAnalyzer.assess(parsed: message.parsed)
        #expect(assessment?.sourceHeaderName == "X-MS-Exchange-Organization-SCL")
        #expect(assessment?.percentage == 100)
    }

    @Test("Rescales an Rspamd score relative to its own required-score threshold")
    func rescalesRspamdScore() throws {
        let message = try makeTestMessage("X-Rspamd-Score: -9.58 / 15.00 / 15.00\r\n\r\n")
        let assessment = SpamLikelihoodAnalyzer.assess(parsed: message.parsed)
        #expect(assessment?.sourceHeaderName == "X-Rspamd-Score")
        #expect(assessment?.percentage == 0) // clamped: -9.58/15*50 is negative
    }

    @Test("Skips a blank X-MBO-SPAM-Probability header instead of crashing, falling through to the next source")
    func skipsBlankMBOHeader() throws {
        let message = try makeTestMessage("X-MBO-SPAM-Probability: \r\nX-Rspamd-Score: 20 / 15.00\r\n\r\n")
        let assessment = SpamLikelihoodAnalyzer.assess(parsed: message.parsed)
        #expect(assessment?.sourceHeaderName == "X-Rspamd-Score")
    }

    @Test("Interprets a fractional X-MBO-SPAM-Probability as 0-1, rescaled to a percentage")
    func interpretsMBOFraction() throws {
        let message = try makeTestMessage("X-MBO-SPAM-Probability: 0.75\r\n\r\n")
        let assessment = SpamLikelihoodAnalyzer.assess(parsed: message.parsed)
        #expect(assessment?.sourceHeaderName == "X-MBO-SPAM-Probability")
        #expect(assessment?.percentage == 75)
    }

    @Test("Returns nil when no recognized spam-scoring header is present")
    func returnsNilWithoutRecognizedHeader() throws {
        let message = try makeTestMessage("From: a@b.com\r\n\r\n")
        #expect(SpamLikelihoodAnalyzer.assess(parsed: message.parsed) == nil)
    }
}
