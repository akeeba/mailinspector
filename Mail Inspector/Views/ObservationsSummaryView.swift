//
//  Mail Inspector
//
//  Copyright (c) 2026 Nicholas K. Dionysopoulos
//  Licensed under the MIT License. See license.txt in the project root for details.
//

import SwiftUI

/// A concise summary of noteworthy observations, gathered from every analyzer. Deliberately not
/// a single score — severity labels and plain descriptions only, so the reader forms their own
/// judgment rather than anchoring on one number.
struct ObservationsSummaryView: View {
    let observations: [SecurityObservation]

    var body: some View {
        if !observations.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Noteworthy Observations")
                    .font(.headline)
                ForEach(observations.sorted(by: { $0.severity > $1.severity })) { observation in
                    HStack(alignment: .top, spacing: 8) {
                        // Severity is otherwise conveyed only by icon shape and color, which
                        // VoiceOver can't see — give it an explicit spoken label.
                        Image(systemName: observation.severity.symbolName)
                            .foregroundStyle(observation.severity.tintColor)
                            .frame(width: 18)
                            .accessibilityLabel(accessibilityLabel(for: observation.severity))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(observation.title)
                                .font(.body.weight(.medium))
                            Text(observation.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.05)))
        }
    }

    private func accessibilityLabel(for severity: ObservationSeverity) -> String {
        switch severity {
        case .warning: return "Warning"
        case .notable: return "Notable"
        case .info: return "Informational"
        }
    }
}
