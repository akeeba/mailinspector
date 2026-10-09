//
//  Mail Inspector
//
//  Copyright (c) 2026 Nicholas K. Dionysopoulos
//  Licensed under the MIT License. See license.txt in the project root for details.
//

import Foundation
import Observation

/// Bridges file URLs handed to the app outside SwiftUI's own view hierarchy.
///
/// Currently this is just Dock-icon drops, which AppKit delivers to
/// `NSApplicationDelegate.application(_:open:)` rather than through any SwiftUI view.
@Observable
@MainActor
final class PendingImportQueue {
    private(set) var urls: [URL] = []

    func enqueue(_ newURLs: [URL]) {
        urls.append(contentsOf: newURLs)
    }

    func drain() -> [URL] {
        defer { urls.removeAll() }
        return urls
    }
}
