//
//  Mail Inspector
//
//  Copyright (c) 2026 Nicholas K. Dionysopoulos / Akeeba Ltd
//  Licensed under the MIT License. See license.txt in the project root for details.
//

import Foundation
import Observation

/// Holds one `MessageInsightsSession` per message so the automatic score/analysis never re-runs
/// when switching back to a previously viewed message, and so the score can be reflected in
/// `SummaryBlocksView`/the PDF export without threading it through as a callback everywhere.
///
/// A plain typed dictionary: now that `MessageInsightsSession` carries no `@available`
/// annotation of its own (every backend-specific requirement lives in whichever `AIAnalysisEngine`
/// it holds), this cache no longer needs to erase to `AnyObject` to stay injectable as a SwiftUI
/// environment object from always-available code.
///
/// `@Observable` tracks access to `sessions` dynamically, so code that reads through this cache
/// (e.g. `MessageDetailView`'s summary-block score) still re-renders correctly once a session is
/// created or its contents change — no manual invalidation needed.
@MainActor
@Observable
final class AIInsightsSessionCache {
    private var sessions: [UUID: MessageInsightsSession] = [:]

    func existingSession(for id: UUID) -> MessageInsightsSession? {
        sessions[id]
    }

    func getOrCreateSession(for id: UUID, factory: () -> MessageInsightsSession) -> MessageInsightsSession {
        if let existing = sessions[id] {
            return existing
        }
        let created = factory()
        sessions[id] = created
        return created
    }

    func removeSession(for id: UUID) {
        sessions[id] = nil
    }
}
