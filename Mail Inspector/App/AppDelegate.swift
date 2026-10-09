//
//  Mail Inspector
//
//  Copyright (c) 2026 Nicholas K. Dionysopoulos
//  Licensed under the MIT License. See license.txt in the project root for details.
//

import AppKit

/// Handles app-lifecycle events SwiftUI's `App` protocol doesn't expose directly — specifically,
/// files (or `.eml`s materialized from a Mail message) dropped on the Dock icon.
///
/// Declaring `CFBundleDocumentTypes` (needed so the Dock icon recognizes `.eml` drops at all —
/// confirmed empirically: without it, or with `CFBundleTypeRole: "None"`, Dock drops are
/// rejected outright and `application(_:open:)` is never even called) has a side effect for a
/// plain `WindowGroup`-based app: macOS treats the dropped file as "a document this app
/// declares it can open" and has SwiftUI present it in a *new* window automatically, separate
/// from this delegate method — confirmed by logging `NSApp.windows.count`, which was already 2
/// by the time `application(_:open:)` ran. There's no declarative way found to suppress that
/// auto-presentation while keeping Dock recognition (both `CFBundleTypeRole: "None"` and
/// removing the declaration disable Dock recognition entirely), so this closes that extra
/// window programmatically instead, keeping the one window this app actually uses.
final class AppDelegate: NSObject, NSApplicationDelegate {
    let pendingImports = PendingImportQueue()
    private weak var mainWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Best-effort cleanup of any promised-file temp directories left behind by a previous
        // run that crashed or was force-quit before it could clean up after itself.
        let promisedFilesRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("MailInspectorPromisedFiles", isDirectory: true)
        try? FileManager.default.removeItem(at: promisedFilesRoot)

        // Captured once, shortly after the app's one real window has had a chance to appear.
        // This is the window every later Dock-drop-triggered "phantom" window gets compared
        // against and closed in favor of.
        DispatchQueue.main.async { [weak self] in
            self?.mainWindow = NSApp.windows.first
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        pendingImports.enqueue(urls)

        DispatchQueue.main.async {
            guard let mainWindow = self.mainWindow, NSApp.windows.count > 1 else { return }
            for window in NSApp.windows where window !== mainWindow {
                window.close()
            }
            mainWindow.makeKeyAndOrderFront(nil)
        }
    }
}
