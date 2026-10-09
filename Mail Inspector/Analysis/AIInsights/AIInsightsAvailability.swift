//
//  Mail Inspector
//
//  Copyright (c) 2026 Nicholas K. Dionysopoulos
//  Licensed under the MIT License. See license.txt in the project root for details.
//

import FoundationModels

/// Whether Apple Intelligence's on-device model is available right now. This type itself carries
/// no `@available` annotation — unlike everything else under `AIInsights/` — specifically so it
/// can be queried unconditionally from code that still has to run on macOS 15, by guarding its
/// one `FoundationModels` reference with `if #available` internally rather than pushing that
/// requirement onto every caller.
///
/// Gated at macOS 27, not 26: see `MessageInsightsSession`'s doc comment — `LanguageModelError`
/// is only available from macOS 27 on this SDK, so the whole feature needs that floor.
nonisolated enum AIInsightsAvailability: Sendable, Equatable {
    case available
    case unavailable(reason: String)

    static var current: AIInsightsAvailability {
        guard #available(macOS 27, *) else {
            return .unavailable(reason: "Requires macOS 27 or later.")
        }
        switch SystemLanguageModel.default.availability {
        case .available:
            return .available
        case .unavailable(.appleIntelligenceNotEnabled):
            return .unavailable(reason: "Turn on Apple Intelligence in System Settings to use this.")
        case .unavailable(.deviceNotEligible):
            return .unavailable(reason: "This Mac doesn't support Apple Intelligence.")
        case .unavailable(.modelNotReady):
            return .unavailable(reason: "The on-device model is still downloading or isn't ready yet. Try again shortly.")
        case .unavailable:
            return .unavailable(reason: "Apple Intelligence currently isn't available.")
        }
    }
}
