//
//  Mail Inspector
//
//  Copyright (c) 2026 Nicholas K. Dionysopoulos / Akeeba Ltd
//  Licensed under the MIT License. See license.txt in the project root for details.
//

import Foundation

/// Decides whether a brand (BIMI) image should even be attempted for a message — purely from
/// settings and already-computed analysis, with no DNS or network access of its own. Kept
/// separate from `BrandImageResolver` so this decision is trivially unit-testable.
nonisolated enum BrandImagePolicy {
    static func shouldAttempt(
        dmarcVerdict: AuthenticationVerdict,
        spamAssessment: SpamLikelihoodAssessment?,
        isEnabled: Bool,
        hideWithoutSpamScore: Bool,
        hideAboveSpamThreshold: Double
    ) -> Bool {
        guard isEnabled else { return false }
        // "Conclusive pass" — only a verdict derived from a trusted Authentication-Results
        // report counts; see AuthenticationAnalyzer's trust model.
        guard dmarcVerdict == .pass else { return false }

        guard let spamAssessment else {
            return !hideWithoutSpamScore
        }
        return spamAssessment.percentage <= hideAboveSpamThreshold
    }
}
