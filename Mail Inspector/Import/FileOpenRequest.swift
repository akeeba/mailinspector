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
