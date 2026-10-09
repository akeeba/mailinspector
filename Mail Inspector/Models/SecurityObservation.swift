import Foundation

nonisolated enum ObservationSeverity: String, Sendable, Comparable {
    case info
    case notable
    case warning

    private var rank: Int {
        switch self {
        case .info: return 0
        case .notable: return 1
        case .warning: return 2
        }
    }

    static func < (lhs: ObservationSeverity, rhs: ObservationSeverity) -> Bool { lhs.rank < rhs.rank }
}

/// A single noteworthy observation surfaced to the user — a discrepancy, anomaly, or simply a
/// fact worth knowing. Never a verdict on whether the message is safe or malicious; always
/// phrased as "here's what was observed", leaving interpretation to the person reading it.
nonisolated struct SecurityObservation: Sendable, Identifiable {
    let id: Int
    let severity: ObservationSeverity
    let title: String
    let detail: String
}
