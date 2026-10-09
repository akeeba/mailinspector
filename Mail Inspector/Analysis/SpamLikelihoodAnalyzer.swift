//
//  Mail Inspector
//
//  Copyright (c) 2026 Nicholas K. Dionysopoulos
//  Licensed under the MIT License. See license.txt in the project root for details.
//

import Foundation

/// A spam-likelihood reading derived from a value a mail filter already reported — never
/// something this app computed independently. The percentage is a heuristic rescaling of that
/// filter's own number onto a common 0–100 display; it is not a calibrated probability, and it
/// is only ever shown when the user has explicitly opted in (`InspectorSettings.trustServerSpamHeaders`)
/// to treating filter-reported headers as meaningful.
nonisolated struct SpamLikelihoodAssessment: Sendable {
    let percentage: Double
    let qualitativeLabel: String
    let sourceHeaderName: String
    let rawValue: String
}

/// Derives a spam-likelihood gauge reading from whichever known spam-scoring header is present,
/// in order of preference. This never implements any scoring logic of its own — it only
/// rescales a number a filter already computed onto a common 0–100 range so results from
/// different filters can be shown the same way.
nonisolated enum SpamLikelihoodAnalyzer {
    static func assess(parsed: ParsedEmail) -> SpamLikelihoodAssessment? {
        if let header = parsed.firstHeader(named: "X-Spam-Score"),
           let score = Double(header.unfoldedValue.trimmingCharacters(in: .whitespaces)) {
            return assessment(fromSpamAssassinStyleScore: score, headerName: "X-Spam-Score", rawValue: header.unfoldedValue)
        }

        if let header = parsed.firstHeader(named: "X-Spam-Status"),
           let score = extractScore(fromStatusLine: header.unfoldedValue) {
            return assessment(fromSpamAssassinStyleScore: score, headerName: "X-Spam-Status", rawValue: "score=\(score)")
        }

        if let header = parsed.firstHeader(named: "X-MS-Exchange-Organization-SCL"),
           let scl = Double(header.unfoldedValue.trimmingCharacters(in: .whitespaces)), scl >= 0 {
            let percentage = clamp(scl / 9 * 100)
            return SpamLikelihoodAssessment(
                percentage: percentage,
                qualitativeLabel: label(for: percentage),
                sourceHeaderName: "X-MS-Exchange-Organization-SCL",
                rawValue: header.unfoldedValue
            )
        }

        if let header = parsed.firstHeader(named: "X-Rspamd-Score"),
           let (score, required) = extractRspamdScore(header.unfoldedValue) {
            // Rspamd has no fixed scale — it's whatever "required_score" the deployment chose —
            // so rescale relative to that threshold instead of a hardcoded range: the required
            // score itself lands at 50%, 0 lands at 0%.
            let percentage = required > 0 ? clamp(score / required * 50) : clamp((score + 5) / 20 * 100)
            return SpamLikelihoodAssessment(
                percentage: percentage,
                qualitativeLabel: label(for: percentage),
                sourceHeaderName: "X-Rspamd-Score",
                rawValue: header.unfoldedValue
            )
        }

        if let header = parsed.firstHeader(named: "X-MBO-SPAM-Probability"),
           let probability = extractProbability(header.unfoldedValue) {
            let percentage = clamp(probability)
            return SpamLikelihoodAssessment(
                percentage: percentage,
                qualitativeLabel: label(for: percentage),
                sourceHeaderName: "X-MBO-SPAM-Probability",
                rawValue: header.unfoldedValue
            )
        }

        return nil
    }

    /// Rspamd's header is conventionally "score / required_score" or
    /// "score / required_score / reject_score"; returns the first two numbers, if parseable.
    private static func extractRspamdScore(_ text: String) -> (score: Double, required: Double)? {
        let components = text.split(separator: "/").map { $0.trimmingCharacters(in: .whitespaces) }
        guard components.count >= 2, let score = Double(components[0]), let required = Double(components[1]) else {
            return nil
        }
        return (score, required)
    }

    /// mailbox.org's header can be blank (no value computed for this message) or a bare number;
    /// since the exact scale isn't documented, treat a fraction (<=1) as 0-1 and anything larger
    /// as an already-a-percentage value.
    private static func extractProbability(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let value = Double(trimmed) else { return nil }
        return value <= 1 ? value * 100 : value
    }

    /// SpamAssassin-style scores have no fixed ceiling, but a score of 5 is the conventional
    /// spam threshold used by most deployments, and scores rarely exceed ~15 in practice. This
    /// maps -5...15 onto 0%...100%, clamping outside that range.
    private static func assessment(fromSpamAssassinStyleScore score: Double, headerName: String, rawValue: String) -> SpamLikelihoodAssessment {
        let percentage = clamp((score + 5) / 20 * 100)
        return SpamLikelihoodAssessment(percentage: percentage, qualitativeLabel: label(for: percentage), sourceHeaderName: headerName, rawValue: rawValue)
    }

    private static func extractScore(fromStatusLine text: String) -> Double? {
        guard let regex = try? NSRegularExpression(pattern: "score=(-?[0-9.]+)") else { return nil }
        let ns = text as NSString
        guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)), match.numberOfRanges > 1 else {
            return nil
        }
        return Double(ns.substring(with: match.range(at: 1)))
    }

    private static func clamp(_ value: Double) -> Double {
        min(100, max(0, value))
    }

    private static func label(for percentage: Double) -> String {
        switch percentage {
        case ..<33: return "Low"
        case ..<66: return "Medium"
        default: return "High"
        }
    }
}
