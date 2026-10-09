//
//  Mail Inspector
//
//  Copyright (c) 2026 Nicholas K. Dionysopoulos / Akeeba Ltd
//  Licensed under the MIT License. See license.txt in the project root for details.
//

import CoreGraphics

/// Common page sizes for the exported PDF report, in points (72pt/inch), portrait orientation.
nonisolated enum ReportPageSize: String, CaseIterable, Identifiable, Sendable {
    case usLetter
    case legal
    case a4
    case a5

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .usLetter: return "US Letter"
        case .legal: return "US Legal"
        case .a4: return "A4"
        case .a5: return "A5"
        }
    }

    var pointSize: CGSize {
        switch self {
        case .usLetter: return CGSize(width: 612, height: 792)
        case .legal: return CGSize(width: 612, height: 1008)
        case .a4: return CGSize(width: 595, height: 842)
        case .a5: return CGSize(width: 420, height: 595)
        }
    }
}
