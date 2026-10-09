import AppKit
import SwiftUI

/// A dropped item awaiting import.
///
/// `isTemporary` distinguishes files Mail Inspector itself wrote out to fulfil a drag promise
/// (which must be deleted after parsing) from files the user already owns, such as a Finder
/// `.eml` (which must never be touched).
struct DroppedItem: Sendable {
    let url: URL
    let isTemporary: Bool
}

/// Installs a window-level drag destination so files can be dropped anywhere in the window, not
/// just on the empty-state `DropZoneView` (which only exists while the message list is empty).
///
/// This cannot be done with a plain `NSView` registered for dragged types and inserted via
/// `.background()`: SwiftUI's `NSHostingView` — the window's real content view, and itself an
/// `NSDraggingDestination` used to back `.onDrop(of:)` — sits above any nested
/// `NSViewRepresentable` view in the hit-tested drag-destination search and never forwards drags
/// of types none of its own `.onDrop` modifiers declared. (Confirmed empirically: a nested view
/// registered via `.background()` never received `draggingEntered` at all.) Registering the
/// `NSWindow` itself for dragged types is a separate, parallel mechanism — `NSWindow` forwards
/// `NSDraggingDestination` messages to its `delegate` when registered this way — so this installs
/// a delegate that handles drag messages itself and transparently forwards every other
/// `NSWindowDelegate` call to whatever delegate SwiftUI already installed, to avoid breaking
/// window lifecycle behavior SwiftUI relies on.
///
/// **Known macOS limitation, confirmed by hands-on testing — twice, with two different
/// destination mechanisms and two different registered-type sets:** dragging a message directly
/// from Apple Mail's list onto *any* third-party application window — this one included — never
/// even reaches `draggingEntered`. This was first confirmed registering only
/// `NSFilePromiseReceiver`'s types + `.fileURL`; dragging the same message into Notes/TextEdit/
/// Calendar/Reminders was later found to insert a `message:<id>` URL, proving Mail's drag source
/// does vend *something* generically droppable — so the types above were broadened to add `.URL`
/// and `.string` and retested, and `draggingEntered` *still* never fired. That rules out "wrong
/// pasteboard type" as the explanation. The most plausible remaining explanation: Mail's drag
/// source special-cases which destinations it considers valid (an allowlist of first-party Apple
/// app bundle IDs, or a private entitlement), which a third-party app has no way to obtain. The
/// same message dragged onto the Finder desktop successfully materializes a `.eml` file there,
/// and that resulting file drags onto this window's `DropZoneView` without issue, which rules out
/// a registration bug on our side generally. Dragging the same message onto this app's **Dock
/// icon**, however, does work (routed through `AppDelegate.application(_:open:)` and
/// `PendingImportQueue`, not this file at all) — that is the supported way to hand this app a
/// Mail message without opening it, and `DropZoneView`'s copy says so. Do not re-attempt a
/// types-based fix here without genuinely new information (e.g. a macOS update) — this has been
/// investigated thoroughly, not guessed at.
struct MailDropReceiver: NSViewRepresentable {
    var onReceiveItems: ([DroppedItem]) -> Void
    var onDraggingStateChanged: (Bool) -> Void = { _ in }

    func makeNSView(context: Context) -> NSView {
        let probe = NSView(frame: .zero)
        DispatchQueue.main.async { install(on: probe, coordinator: context.coordinator) }
        return probe
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onReceiveItems = onReceiveItems
        context.coordinator.onDraggingStateChanged = onDraggingStateChanged
        install(on: nsView, coordinator: context.coordinator)
    }

    func makeCoordinator() -> WindowDragDestination {
        let coordinator = WindowDragDestination()
        coordinator.onReceiveItems = onReceiveItems
        coordinator.onDraggingStateChanged = onDraggingStateChanged
        return coordinator
    }

    private func install(on view: NSView, coordinator: WindowDragDestination) {
        guard let window = view.window, window.delegate !== coordinator else { return }
        coordinator.previousDelegate = window.delegate
        window.delegate = coordinator
        window.registerForDraggedTypes(WindowDragDestination.acceptedTypes)
    }
}

/// Handles window-level drag messages and forwards any other `NSWindowDelegate` call to
/// whatever delegate SwiftUI had installed, so this doesn't interfere with window lifecycle
/// behavior SwiftUI manages through that delegate.
final class WindowDragDestination: NSObject, NSWindowDelegate {
    // AppKit always calls delegate methods on the main thread; these overrides must be
    // `nonisolated` to match NSObject's signatures, so this needs an isolation escape hatch.
    nonisolated(unsafe) weak var previousDelegate: NSWindowDelegate?
    var onReceiveItems: (([DroppedItem]) -> Void)?
    var onDraggingStateChanged: ((Bool) -> Void)?

    static let acceptedTypes: [NSPasteboard.PasteboardType] = {
        let promiseTypes: [NSPasteboard.PasteboardType] = NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) }
        return promiseTypes + [.fileURL]
    }()

    func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        onDraggingStateChanged?(true)
        return .copy
    }

    func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        .copy
    }

    func draggingExited(_ sender: NSDraggingInfo?) {
        onDraggingStateChanged?(false)
    }

    func draggingEnded(_ sender: NSDraggingInfo) {
        onDraggingStateChanged?(false)
    }

    func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        var directURLs: [URL] = []
        var promiseReceivers: [NSFilePromiseReceiver] = []

        sender.enumerateDraggingItems(
            options: [],
            for: nil,
            classes: [NSFilePromiseReceiver.self, NSURL.self],
            searchOptions: [:]
        ) { draggingItem, _, _ in
            if let receiver = draggingItem.item as? NSFilePromiseReceiver {
                promiseReceivers.append(receiver)
            } else if let url = draggingItem.item as? URL {
                directURLs.append(url)
            }
        }

        guard !directURLs.isEmpty || !promiseReceivers.isEmpty else { return false }

        if !directURLs.isEmpty {
            onReceiveItems?(directURLs.map { DroppedItem(url: $0, isTemporary: false) })
        }

        if !promiseReceivers.isEmpty {
            receivePromises(promiseReceivers)
        }

        return true
    }

    /// Fulfils each file promise into a freshly created, per-drop temporary directory. The
    /// importer is responsible for deleting these files once it has finished reading them — Mail
    /// never hands us an existing `.eml` to begin with here, this app materializes one itself.
    private func receivePromises(_ receivers: [NSFilePromiseReceiver]) {
        let destinationDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MailInspectorPromisedFiles", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        guard (try? FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)) != nil else {
            return
        }

        let queue = OperationQueue()
        for receiver in receivers {
            receiver.receivePromisedFiles(atDestination: destinationDirectory, options: [:], operationQueue: queue) { url, error in
                guard error == nil else { return }
                DispatchQueue.main.async { [weak self] in
                    self?.onReceiveItems?([DroppedItem(url: url, isTemporary: true)])
                }
            }
        }
    }

    // MARK: - Transparent forwarding of every other NSWindowDelegate call

    nonisolated override func responds(to aSelector: Selector!) -> Bool {
        if super.responds(to: aSelector) { return true }
        return previousDelegate?.responds(to: aSelector) ?? false
    }

    nonisolated override func forwardingTarget(for aSelector: Selector!) -> Any? {
        if super.responds(to: aSelector) { return nil }
        return previousDelegate
    }
}
