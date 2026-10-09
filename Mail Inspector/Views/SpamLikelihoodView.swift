//
//  Mail Inspector
//
//  Copyright (c) 2026 Nicholas K. Dionysopoulos / Akeeba Ltd
//  Licensed under the MIT License. See license.txt in the project root for details.
//

import SwiftUI

/// Shown only when the user has opted in (Settings → "Trust server spam headers") and a known
/// spam-scoring header is present. The gauge reflects what a filter already reported, not an
/// independent assessment — the caption always says so.
struct SpamLikelihoodView: View {
    let assessment: SpamLikelihoodAssessment

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Spam Likelihood")
                .font(.headline)
            HStack(spacing: 16) {
                Gauge(value: assessment.percentage, in: 0...100) {
                    Text("Spam")
                } currentValueLabel: {
                    Text("\(Int(assessment.percentage.rounded()))%")
                }
                .gaugeStyle(.accessoryCircular)
                .tint(tintColor)
                .accessibilityLabel("Spam likelihood: \(assessment.qualitativeLabel), \(Int(assessment.percentage.rounded())) percent")

                VStack(alignment: .leading, spacing: 4) {
                    Text(assessment.qualitativeLabel)
                        .font(.body.weight(.medium))
                    Text("As reported by \(assessment.sourceHeaderName) (\(assessment.rawValue)) — your mail provider's filter computed this, not this app. It is not a guarantee of safety.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.05)))
    }

    private var tintColor: Color {
        switch assessment.percentage {
        case ..<33: return .green
        case ..<66: return .orange
        default: return .red
        }
    }
}
