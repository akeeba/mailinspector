//
//  Mail Inspector
//
//  Copyright (c) 2026 Nicholas K. Dionysopoulos
//  Licensed under the MIT License. See license.txt in the project root for details.
//

import Foundation
import Observation

/// Holds one `MessageInsightsSession` per message so the automatic score/analysis never re-runs
/// when switching back to a previously viewed message, and so the score can be reflected in
/// `SummaryBlocksView`/the PDF export without threading it through as a callback everywhere.
///
/// Deliberately carries no `@available` annotation and stores `AnyObject`, not
/// `MessageInsightsSession` — that type requires macOS 27, but this cache is injected as a
/// SwiftUI environment object from always-available code (`MailInspectorApp`, `ContentView`),
/// which must keep compiling on this app's macOS 15 deployment target. Callers that are already
/// inside an `if #available(macOS 27, *)` block cast the result back with
/// `as? MessageInsightsSession`.
///
/// `@Observable` tracks access to `sessions` dynamically, regardless of what's erased inside it,
/// so code that reads through this cache (even from outside the availability-gated branch, e.g.
/// `MessageDetailView`'s summary-block score) still re-renders correctly once a session is
/// created or its contents change — no manual invalidation needed.
@MainActor
@Observable
final class AIInsightsSessionCache {
    private var sessions: [UUID: AnyObject] = [:]

    func existingSession(for id: UUID) -> AnyObject? {
        sessions[id]
    }

    func getOrCreateSession(for id: UUID, factory: () -> AnyObject) -> AnyObject {
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
