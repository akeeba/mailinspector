//
//  Mail Inspector
//
//  Copyright (c) 2026 Nicholas K. Dionysopoulos
//  Licensed under the MIT License. See license.txt in the project root for details.
//

import SwiftUI

/// Shared icon/color mapping for `ObservationSeverity`, used anywhere severity is shown
/// visually (the observations summary, delivery-path hops, the Hops summary block, the
/// exported report). Kept out of `Models/SecurityObservation.swift` since that type is
/// otherwise UI-framework-free.
extension ObservationSeverity {
    var symbolName: String {
        switch self {
        case .warning: return "exclamationmark.triangle.fill"
        case .notable: return "info.circle.fill"
        case .info: return "checkmark.circle"
        }
    }

    var tintColor: Color {
        switch self {
        case .warning: return .orange
        case .notable: return .blue
        case .info: return .secondary
        }
    }
}
