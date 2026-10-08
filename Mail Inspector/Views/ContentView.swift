import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var messages: [EmailMessage] = []
    @State private var selection: EmailMessage.ID?
    @State private var isImporterPresented = false
    @State private var importErrorMessage: String?
    @State private var isDropTargeted = false
    @Environment(InspectorSettings.self) private var settings
    @Environment(PendingImportQueue.self) private var pendingImports

    private static var emlContentTypes: [UTType] {
        [UTType(filenameExtension: "eml") ?? .data]
    }

    var body: some View {
        NavigationSplitView {
            List(messages, selection: $selection) { message in
                MessageRow(message: message)
                    .tag(message.id)
            }
            .navigationTitle("Messages")
            .overlay {
                if messages.isEmpty {
                    ContentUnavailableView(
                        "No Messages",
                        systemImage: "tray",
                        description: Text("Import an email to see it here.")
                    )
                }
            }
            .toolbar {
                ToolbarItem {
                    Button {
                        isImporterPresented = true
                    } label: {
                        Label("Open Email File…", systemImage: "plus")
                    }
                }
            }
        } detail: {
            if let selection, let message = messages.first(where: { $0.id == selection }) {
                MessageDetailView(message: message)
            } else if messages.isEmpty {
                DropZoneView(onImportURLs: { importItems($0.map { DroppedItem(url: $0, isTemporary: false) }) }, onOpenFile: { isImporterPresented = true })
            } else {
                ContentUnavailableView("Select a Message", systemImage: "envelope")
            }
        }
        // Covers the whole window so a message dragged from Apple Mail's list (delivered as a
        // file promise, which SwiftUI's own `onDrop` cannot receive) can be dropped anywhere,
        // not just on the empty-state drop zone.
        .background(
            MailDropReceiver(
                onReceiveItems: importItems,
                onDraggingStateChanged: { isDropTargeted = $0 }
            )
        )
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 0)
                    .strokeBorder(Color.accentColor, lineWidth: 3)
                    .allowsHitTesting(false)
            }
        }
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: Self.emlContentTypes,
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                importItems(urls.map { DroppedItem(url: $0, isTemporary: false) })
            case .failure(let error):
                importErrorMessage = error.localizedDescription
            }
        }
        .alert(
            "Import Failed",
            isPresented: Binding(
                get: { importErrorMessage != nil },
                set: { if !$0 { importErrorMessage = nil } }
            )
        ) {
            Button("OK") { importErrorMessage = nil }
        } message: {
            Text(importErrorMessage ?? "")
        }
        .task {
            drainPendingImports()
        }
        .task {
            // The one network request this app ever makes, and only when enabled in Settings;
            // it no-ops entirely (no network access) once a week's worth of cache is fresh.
            if settings.isPublicSuffixListUpdateEnabled {
                await PublicSuffixList.shared.refreshIfNeeded()
            }
        }
        .onChange(of: pendingImports.urls) { _, newValue in
            guard !newValue.isEmpty else { return }
            drainPendingImports()
        }
    }

    /// Picks up files handed to the app via the Dock icon (delivered to the app delegate, not
    /// through any SwiftUI view), regardless of whether that happened before or after this view
    /// first appeared.
    private func drainPendingImports() {
        let urls = pendingImports.drain()
        guard !urls.isEmpty else { return }
        importItems(urls.map { DroppedItem(url: $0, isTemporary: false) })
    }

    private func importItems(_ items: [DroppedItem]) {
        for item in items {
            Task {
                do {
                    let message = try await EmailImportCoordinator.importMessage(
                        from: item.url,
                        maxMessageSize: settings.maxMessageSizeBytes
                    )
                    messages.append(message)
                    selection = message.id
                } catch {
                    importErrorMessage = (error as? LocalizedError)?.errorDescription
                        ?? "“\(item.url.lastPathComponent)” could not be imported."
                }
                if item.isTemporary {
                    try? FileManager.default.removeItem(at: item.url)
                }
            }
        }
    }
}

private struct MessageRow: View {
    let message: EmailMessage

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(message.primaryFrom?.address ?? "Unknown sender")
                .font(.body)
                .lineLimit(1)
            Text(message.subject ?? "(No Subject)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if let date = message.date {
                Text(date.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }
}
