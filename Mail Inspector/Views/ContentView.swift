//
//  Mail Inspector
//
//  Copyright (c) 2026 Nicholas K. Dionysopoulos / Akeeba Ltd
//  Licensed under the MIT License. See license.txt in the project root for details.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var messages: [EmailMessage] = []
    @State private var selection: EmailMessage.ID?
    @State private var isImporterPresented = false
    @State private var importErrorMessage: String?
    @State private var isDropTargeted = false
    @Environment(InspectorSettings.self) private var settings
    @Environment(PendingImportQueue.self) private var pendingImports
    @Environment(FileOpenRequest.self) private var fileOpenRequest
    @Environment(ReportExportRequest.self) private var reportExportRequest
    @Environment(AIInsightsSessionCache.self) private var aiInsightsSessionCache

    private var selectedMessage: EmailMessage? {
        messages.first { $0.id == selection }
    }

    private static var emlContentTypes: [UTType] {
        [UTType(filenameExtension: "eml") ?? .data]
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(messages) { message in
                    MessageRow(message: message)
                        .tag(message.id)
                        .contextMenu {
                            Button("Remove from List", role: .destructive) {
                                remove(message.id)
                            }
                        }
                }
                .onDelete { offsets in
                    for index in offsets { remove(messages[index].id) }
                }
            }
            .onDeleteCommand {
                if let selection { remove(selection) }
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
                if selectedMessage != nil {
                    ToolbarItem {
                        Button {
                            shareSelectedMessageAsPDF()
                        } label: {
                            Label("Share Report…", systemImage: "square.and.arrow.up")
                        }
                        .accessibilityLabel("Share report as PDF")
                    }
                }
                ToolbarItem {
                    Button {
                        isImporterPresented = true
                    } label: {
                        Label("Open Email File…", systemImage: "plus")
                    }
                }
            }
            .onDrop(of: [UTType.fileURL], isTargeted: $isDropTargeted) { providers in
                handleItemProviders(providers)
                return true
            }
        } detail: {
            Group {
                if let selection, let message = messages.first(where: { $0.id == selection }) {
                    MessageDetailView(message: message, onDelete: { remove(message.id) })
                } else if messages.isEmpty {
                    DropZoneView(onImportURLs: { importItems($0.map { DroppedItem(url: $0, isTemporary: false) }) }, onOpenFile: { isImporterPresented = true })
                } else {
                    ContentUnavailableView("Select a Message", systemImage: "envelope")
                }
            }
            .onDrop(of: [UTType.fileURL], isTargeted: $isDropTargeted) { providers in
                handleItemProviders(providers)
                return true
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
            // One of only two network requests this app ever makes, and only when enabled in
            // Settings; it no-ops entirely (no network access) once a week's worth of cache is
            // fresh. (The other is the manually-triggered SPF recheck in AuthenticationView.)
            if settings.isPublicSuffixListUpdateEnabled {
                await PublicSuffixList.shared.refreshIfNeeded()
            }
        }
        .onChange(of: pendingImports.urls) { _, newValue in
            guard !newValue.isEmpty else { return }
            drainPendingImports()
        }
        .onChange(of: fileOpenRequest.token) { _, _ in
            isImporterPresented = true
        }
        .onChange(of: reportExportRequest.exportToken) { _, _ in
            exportSelectedMessageAsPDF()
        }
        .onChange(of: reportExportRequest.shareToken) { _, _ in
            shareSelectedMessageAsPDF()
        }
    }

    /// ⌘E and the toolbar's "Open Email File…" button both present panels — this one lets the
    /// user pick where to save the rendered report instead of just writing it somewhere fixed.
    private func exportSelectedMessageAsPDF() {
        guard let message = selectedMessage,
              let pdfData = ReportPDFExporter.renderPDF(for: message, settings: settings, pageSize: settings.reportPageSize, aiInsights: aiExportSummary(for: message)) else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = ReportPDFExporter.suggestedFileName(for: message)
        panel.canCreateDirectories = true

        let completion: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else { return }
            try? pdfData.write(to: url)
        }
        if let window = NSApp.keyWindow {
            panel.beginSheetModal(for: window, completionHandler: completion)
        } else {
            panel.begin(completionHandler: completion)
        }
    }

    /// ⇧⌘E and the toolbar's Share button — renders to a temp file so the system share sheet
    /// (Mail, Messages, AirDrop, Save to Files, …) sees a real PDF with a sensible filename
    /// rather than opaque in-memory data.
    private func shareSelectedMessageAsPDF() {
        guard let message = selectedMessage,
              let pdfData = ReportPDFExporter.renderPDF(for: message, settings: settings, pageSize: settings.reportPageSize, aiInsights: aiExportSummary(for: message)) else { return }

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: tempURL, withIntermediateDirectories: true)
            let fileURL = tempURL.appendingPathComponent(ReportPDFExporter.suggestedFileName(for: message))
            try pdfData.write(to: fileURL)

            guard let contentView = NSApp.keyWindow?.contentView else { return }
            let picker = NSSharingServicePicker(items: [fileURL])
            picker.show(relativeTo: .zero, of: contentView, preferredEdge: .maxY)
        } catch {
            importErrorMessage = "Could not prepare the report for sharing: \(error.localizedDescription)"
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

    private func remove(_ id: EmailMessage.ID) {
        messages.removeAll { $0.id == id }
        if selection == id { selection = nil }
        aiInsightsSessionCache.removeSession(for: id)
    }

    /// Only ever produces a result if the score/analysis were already generated while viewing
    /// this message — exporting never triggers Apple Intelligence itself, so a message that was
    /// never opened in the detail view simply exports without this section.
    private func aiExportSummary(for message: EmailMessage) -> AIInsightsExportSummary? {
        guard settings.isAIInsightsEnabled else { return nil }
        guard let session = aiInsightsSessionCache.existingSession(for: message.id),
              let assessment = session.assessment,
              let analysisText = session.prefabAnalysis else {
            return nil
        }
        return AIInsightsExportSummary(score: assessment.score, rationale: assessment.rationale, analysisText: analysisText)
    }

    /// Extracts plain file URLs from a Finder-origin drag. Applied directly to the sidebar list
    /// and the detail pane so dropping an `.eml` works whether or not messages are already
    /// loaded — SwiftUI's own `onDrop` on these specific views is more reliable here than
    /// relying solely on the window-level `MailDropReceiver` reaching through a `List`'s own
    /// AppKit-backed drag handling.
    private func handleItemProviders(_ providers: [NSItemProvider]) {
        let group = DispatchGroup()
        let lock = NSLock()
        var collected: [URL] = []

        for provider in providers {
            guard provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) else { continue }
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                defer { group.leave() }
                var url: URL?
                if let data = item as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else if let existing = item as? URL {
                    url = existing
                }
                if let url {
                    lock.lock()
                    collected.append(url)
                    lock.unlock()
                }
            }
        }

        group.notify(queue: .main) {
            if !collected.isEmpty {
                importItems(collected.map { DroppedItem(url: $0, isTemporary: false) })
            }
        }
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
