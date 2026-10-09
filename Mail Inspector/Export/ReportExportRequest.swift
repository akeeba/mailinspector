//
//  Mail Inspector
//
//  Copyright (c) 2026 Nicholas K. Dionysopoulos / Akeeba Ltd
//  Licensed under the MIT License. See license.txt in the project root for details.
//

import Foundation
import Observation

/// A cross-scene signal letting the File ▸ Export/Share menu commands (wired in
/// `MailInspectorApp`) trigger `ContentView`'s PDF export/share logic, since SwiftUI's
/// `.commands` run outside any particular view and have no direct way to read that view's own
/// `@State` (which message is selected). Mirrors `FileOpenRequest`'s pattern.
@Observable
@MainActor
final class ReportExportRequest {
    private(set) var exportToken = UUID()
    private(set) var shareToken = UUID()

    func fireExport() {
        exportToken = UUID()
    }

    func fireShare() {
        shareToken = UUID()
    }
}
