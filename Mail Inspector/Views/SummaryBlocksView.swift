//
//  Mail Inspector
//
//  Copyright (c) 2026 Nicholas K. Dionysopoulos
//  Licensed under the MIT License. See license.txt in the project root for details.
//

import SwiftUI

/// A row of at-a-glance summary blocks — SPF, DKIM, DMARC, delivery-path hops, and (when
/// available) the spam-likelihood score. Each block is a shortcut: tapping it jumps to the
/// corresponding section further down the report, it never shows information found nowhere
/// else in this view.
struct SummaryBlocksView: View {
    let authentication: AuthenticationAnalysis
    let deliveryPath: DeliveryPathAnalysis
    let spamAssessment: SpamLikelihoodAssessment?
    let aiScore: Int?
    /// True while the score itself is still being generated (not the longer prose analysis) —
    /// shows a spinner in the AI block's place rather than waiting for a score to exist before
    /// the block appears at all.
    let aiScoreIsPending: Bool
    let onTapAuthentication: () -> Void
    let onTapHops: () -> Void
    let onTapSpam: () -> Void
    let onTapAI: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            SummaryBlock(
                title: "SPF",
                value: authentication.spf.verdict.displayLabel,
                systemImage: authentication.spf.verdict.symbolName,
                tintColor: authentication.spf.verdict.tintColor,
                action: onTapAuthentication
            )
            SummaryBlock(
                title: "DKIM",
                value: authentication.dkim.verdict.displayLabel,
                systemImage: authentication.dkim.verdict.symbolName,
                tintColor: authentication.dkim.verdict.tintColor,
                action: onTapAuthentication
            )
            SummaryBlock(
                title: "DMARC",
                value: authentication.dmarc.verdict.displayLabel,
                systemImage: authentication.dmarc.verdict.symbolName,
                tintColor: authentication.dmarc.verdict.tintColor,
                action: onTapAuthentication
            )
            SummaryBlock(
                title: "Hops",
                value: "\(deliveryPath.hops.count)",
                systemImage: worstHopSeverity?.symbolName,
                tintColor: worstHopSeverity?.tintColor ?? .primary,
                action: onTapHops
            )
            if let spamAssessment {
                SummaryBlock(
                    title: "Spam Score",
                    value: "\(Int(spamAssessment.percentage.rounded()))%",
                    systemImage: nil,
                    tintColor: spamTintColor(for: spamAssessment.percentage),
                    action: onTapSpam
                )
            }
            if let aiScore {
                SummaryBlock(
                    title: "AI",
                    value: "\(aiScore)%",
                    systemImage: "sparkles",
                    tintColor: aiTintColor(for: aiScore),
                    action: onTapAI
                )
            } else if aiScoreIsPending {
                SummaryBlock(
                    title: "AI",
                    value: "",
                    systemImage: "sparkles",
                    tintColor: .secondary,
                    isLoading: true,
                    action: onTapAI
                )
            }
        }
    }

    /// The most severe flag across every hop, if any. A path with only notices (routine internal
    /// SaaS routing, unresolvable reverse DNS, etc.) should never look like a warning the way an
    /// actually inconsistent or forged-looking hop should.
    private var worstHopSeverity: ObservationSeverity? {
        deliveryPath.hops.flatMap(\.flags).map(\.severity).max()
    }

    private func spamTintColor(for percentage: Double) -> Color {
        switch percentage {
        case ..<33: return .green
        case ..<66: return .orange
        default: return .red
        }
    }

    /// Inverted from `spamTintColor`: high is good here (a legitimacy score), not bad.
    private func aiTintColor(for score: Int) -> Color {
        switch score {
        case ..<33: return .red
        case ..<66: return .orange
        default: return .green
        }
    }
}

private struct SummaryBlock: View {
    let title: String
    let value: String
    let systemImage: String?
    let tintColor: Color
    var isLoading: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    if let systemImage {
                        Image(systemName: systemImage)
                            .font(.title3)
                            .foregroundStyle(tintColor)
                    }
                    Text(value)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(tintColor)
                        .lineLimit(1)
                }
            }
            .frame(minWidth: 88, minHeight: 72)
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.08)))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(isLoading ? "\(title): generating" : "\(title): \(value)")
        .accessibilityHint("Jumps to the \(title) section of the report.")
    }
}
