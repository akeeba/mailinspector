import AppKit

/// Handles app-lifecycle events SwiftUI's `App` protocol doesn't expose directly — specifically,
/// files (or `.eml`s materialized from a Mail message) dropped on the Dock icon.
final class AppDelegate: NSObject, NSApplicationDelegate {
    let pendingImports = PendingImportQueue()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Best-effort cleanup of any promised-file temp directories left behind by a previous
        // run that crashed or was force-quit before it could clean up after itself.
        let promisedFilesRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("MailInspectorPromisedFiles", isDirectory: true)
        try? FileManager.default.removeItem(at: promisedFilesRoot)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        pendingImports.enqueue(urls)
    }
}
