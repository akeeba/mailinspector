# Dock-icon drop fragility

Dock-icon file drops (dragging a `.eml`, or a Mail.app message, onto the app's Dock tile) have
broken twice in this project for two *different* root causes, both stemming from the same
underlying mechanism: declaring `CFBundleDocumentTypes` (required for the Dock icon to recognize
drops at all) makes macOS auto-open a **second, phantom** SwiftUI window for the dropped file,
separate from `AppDelegate.application(_:open:)`. See `build-progress.md` for the full build
history; this doc exists specifically so this mechanism doesn't get re-broken by a future,
unrelated-looking change.

**Break #1 (Phase 2):** the phantom window itself was the bug — two windows ended up open, one
empty. Fixed by having `AppDelegate` capture `NSApp.windows.first` as `mainWindow` shortly after
launch, then in `application(_:open:)` closing every *other* window and bringing `mainWindow`
forward.

**Break #2 (Phase 5, after the bundle identifier/dev-team/icon changes):** the Dock drop appeared
to do nothing — Dock icon flashed, app activated, but no message ever appeared. Root cause was a
race, not a missing fix: `application(_:open:)` called `pendingImports.enqueue(urls)`
*immediately*, and only closed the phantom window afterward on a deferred
`DispatchQueue.main.async`. Both windows' `ContentView` share the same `PendingImportQueue`
instance via `.environment(appDelegate.pendingImports)`, so both observe the enqueue. Whichever
window's `onChange(of: pendingImports.urls)` fired first won the race to drain the queue — if that
was the phantom window, the imported message got appended to *that* window's local
`@State messages`, which was then thrown away the instant the window closed a moment later. Fixed
in `Mail Inspector/App/AppDelegate.swift` by reordering: close the phantom window *first* (still
inside the `DispatchQueue.main.async` block), and only call `pendingImports.enqueue(urls)`
afterward, so only the surviving window's `ContentView` is ever alive to observe the change.

**How to apply:** if Dock-icon drops break again, suspect this exact mechanism first — a phantom
window reappearing, or a reordering of window-close vs. queue-enqueue. Don't touch the relative
order of "close other windows" and "enqueue pending import" in `AppDelegate.application(_:open:)`
without re-verifying both ends: (1) only one window survives, (2) the surviving window's
`ContentView` is the one that actually receives the import. This is also a cautionary example for
any *other* future state shared across multiple windows via `@Environment` in this app — if two
windows can both exist (even transiently) and both observe the same `@Observable` object, whichever
one reacts first wins, and that's only safe if exactly one of them is guaranteed to still be alive
when it matters.
