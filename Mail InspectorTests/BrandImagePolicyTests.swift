//
//  Mail Inspector
//
//  Copyright (c) 2026 Nicholas K. Dionysopoulos
//  Licensed under the MIT License. See license.txt in the project root for details.
//

import Testing
import Foundation
@testable import Mail_Inspector

/// Tests for `BrandImagePolicy`: deciding whether a BIMI brand image should even be attempted,
/// requiring the feature to be enabled and DMARC to be a conclusive (trusted) pass, then further
/// gating on spam likelihood — hiding the image for unscored messages unless explicitly allowed,
/// and hiding it once a message's spam score exceeds the configured threshold.
@Suite("BrandImagePolicy")
struct BrandImagePolicyTests {
    private func makeAssessment(percentage: Double) -> SpamLikelihoodAssessment {
        SpamLikelihoodAssessment(
            percentage: percentage,
            qualitativeLabel: "Test",
            sourceHeaderName: "X-Spam-Score",
            rawValue: "\(percentage)"
        )
    }

    @Test("Never attempts the lookup when the feature is disabled, even with a passing DMARC verdict")
    func disabledFeatureNeverAttempts() {
        let shouldAttempt = BrandImagePolicy.shouldAttempt(
            dmarcVerdict: .pass,
            spamAssessment: nil,
            isEnabled: false,
            hideWithoutSpamScore: false,
            hideAboveSpamThreshold: 100
        )
        #expect(shouldAttempt == false)
    }

    @Test("Does not attempt the lookup unless DMARC is a conclusive pass", arguments: [
        AuthenticationVerdict.fail, .warning, .unverified, .unknown
    ])
    func requiresConclusiveDMARCPass(verdict: AuthenticationVerdict) {
        let shouldAttempt = BrandImagePolicy.shouldAttempt(
            dmarcVerdict: verdict,
            spamAssessment: nil,
            isEnabled: true,
            hideWithoutSpamScore: false,
            hideAboveSpamThreshold: 100
        )
        #expect(shouldAttempt == false)
    }

    @Test("Hides the image for a message with no spam score when hideWithoutSpamScore is on")
    func hidesWithoutSpamScoreWhenConfiguredTo() {
        let shouldAttempt = BrandImagePolicy.shouldAttempt(
            dmarcVerdict: .pass,
            spamAssessment: nil,
            isEnabled: true,
            hideWithoutSpamScore: true,
            hideAboveSpamThreshold: 25
        )
        #expect(shouldAttempt == false)
    }

    @Test("Shows the image for a message with no spam score when hideWithoutSpamScore is off")
    func showsWithoutSpamScoreWhenNotConfiguredToHide() {
        let shouldAttempt = BrandImagePolicy.shouldAttempt(
            dmarcVerdict: .pass,
            spamAssessment: nil,
            isEnabled: true,
            hideWithoutSpamScore: false,
            hideAboveSpamThreshold: 25
        )
        #expect(shouldAttempt == true)
    }

    @Test("Shows the image when the spam score is at or below the configured threshold")
    func showsAtOrBelowThreshold() {
        let shouldAttempt = BrandImagePolicy.shouldAttempt(
            dmarcVerdict: .pass,
            spamAssessment: makeAssessment(percentage: 25),
            isEnabled: true,
            hideWithoutSpamScore: true,
            hideAboveSpamThreshold: 25
        )
        #expect(shouldAttempt == true)
    }

    @Test("Hides the image once the spam score exceeds the configured threshold")
    func hidesAboveThreshold() {
        let shouldAttempt = BrandImagePolicy.shouldAttempt(
            dmarcVerdict: .pass,
            spamAssessment: makeAssessment(percentage: 26),
            isEnabled: true,
            hideWithoutSpamScore: true,
            hideAboveSpamThreshold: 25
        )
        #expect(shouldAttempt == false)
    }
}
