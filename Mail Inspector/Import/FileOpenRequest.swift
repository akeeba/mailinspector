//
//  Mail Inspector
//
//  Copyright (c) 2026 Nicholas K. Dionysopoulos / Akeeba Ltd
//  Licensed under the MIT License. See license.txt in the project root for details.
//

import Foundation
import Observation

/// A simple cross-scene signal letting the File ▸ Open… menu command (wired in
/// `MailInspectorApp`) trigger `ContentView`'s file importer, since SwiftUI's `.commands` run
/// outside any particular view and have no direct way to flip that view's own `@State`.
@Observable
@MainActor
final class FileOpenRequest {
    private(set) var token = UUID()

    func fire() {
        token = UUID()
    }
}
