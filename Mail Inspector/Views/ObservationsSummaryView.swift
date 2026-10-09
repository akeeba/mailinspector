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
                        Image(systemName: symbolName(for: observation.severity))
                            .foregroundStyle(color(for: observation.severity))
                            .frame(width: 18)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(observation.title)
                                .font(.body.weight(.medium))
                            Text(observation.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.05)))
        }
    }

    private func symbolName(for severity: ObservationSeverity) -> String {
        switch severity {
        case .warning: return "exclamationmark.triangle.fill"
        case .notable: return "info.circle.fill"
        case .info: return "checkmark.circle"
        }
    }

    private func color(for severity: ObservationSeverity) -> Color {
        switch severity {
        case .warning: return .orange
        case .notable: return .blue
        case .info: return .secondary
        }
    }
}
