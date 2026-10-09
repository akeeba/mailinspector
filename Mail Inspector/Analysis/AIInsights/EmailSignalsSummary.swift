//
//  Mail Inspector
//
//  Copyright (c) 2026 Nicholas K. Dionysopoulos / Akeeba Ltd
//  Licensed under the MIT License. See license.txt in the project root for details.
//

import Foundation

/// Builds a short, plain-text digest of this app's own already-computed signals (SPF/DKIM/DMARC
/// verdicts and alignment, delivery-path flags, sender-identity observations, spam score) — the
/// only thing ever sent into the on-device model's prompt for the legitimacy score and the
/// prefab analysis. Deliberately never includes raw headers or the message body: the on-device
/// model has a 4096-token context window for the whole session, and a condensed digest of
/// signals this app has already extracted is both far more budget-efficient and far less
/// steerable by attacker-controlled text than dumping raw headers would be.
nonisolated enum EmailSignalsSummary {
    static func build(
        message: EmailMessage,
        authentication: AuthenticationAnalysis,
        deliveryPath: DeliveryPathAnalysis,
        senderIdentityObservations: [SecurityObservation],
        spamAssessment: SpamLikelihoodAssessment?
    ) -> String {
        var lines: [String] = []

        lines.append("Subject: \(message.subject ?? "(none)")")
        if let from = message.primaryFrom {
            let displayName = from.displayName.map { "\($0) " } ?? ""
            lines.append("From: \(displayName)<\(from.address)>")
        } else {
            lines.append("From: (could not be parsed)")
        }
        if let returnPath = message.returnPath {
            lines.append("Return-Path: \(returnPath)")
        }

        lines.append("SPF: \(authentication.spf.verdict.rawValue)")
        lines.append("DKIM: \(authentication.dkim.verdict.rawValue)")
        lines.append("DMARC: \(authentication.dmarc.verdict.rawValue)")

        if let fromDomain = authentication.alignment.fromDomain {
            lines.append("DMARC alignment for From domain \(fromDomain):")
            if let spfAlignment = authentication.alignment.spfAlignment, let spfDomain = authentication.alignment.spfCheckedDomain {
                lines.append("- SPF-checked domain \(spfDomain): \(describe(spfAlignment))")
            }
            if let dkimAlignment = authentication.alignment.dkimAlignment, let dkimDomain = authentication.alignment.dkimSigningDomain {
                lines.append("- DKIM-signing domain \(dkimDomain): \(describe(dkimAlignment))")
            }
        }

        lines.append("Delivery hops: \(deliveryPath.hops.count)")
        for hop in deliveryPath.hops {
            for flag in hop.flags where flag.severity >= .notable {
                let hostLabel = hop.claimedFromHostname ?? hop.fromIPAddress ?? "unknown hop"
                lines.append("- Hop (\(hostLabel)) [\(flag.severity.rawValue)]: \(flag.message)")
            }
        }

        for observation in senderIdentityObservations {
            lines.append("- Sender-identity observation [\(observation.severity.rawValue)]: \(observation.title) — \(observation.detail)")
        }

        if let spamAssessment {
            lines.append("Spam filter score: \(Int(spamAssessment.percentage.rounded()))% (\(spamAssessment.qualitativeLabel), reported by \(spamAssessment.sourceHeaderName): \(spamAssessment.rawValue))")
        } else {
            lines.append("Spam filter score: not available")
        }

        return lines.joined(separator: "\n")
    }

    private static func describe(_ alignment: DomainAlignment.Result) -> String {
        switch alignment {
        case .strict: return "aligned (identical domain)"
        case .relaxed: return "aligned (same organizational domain)"
        case .notAligned: return "not aligned"
        }
    }
}
