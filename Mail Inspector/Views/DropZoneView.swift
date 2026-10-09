//
//  Mail Inspector
//
//  Copyright (c) 2026 Nicholas K. Dionysopoulos
//  Licensed under the MIT License. See license.txt in the project root for details.
//

import SwiftUI
import UniformTypeIdentifiers

/// The empty-state drop target shown when no message has been imported yet.
struct DropZoneView: View {
    var onImportURLs: ([URL]) -> Void
    var onOpenFile: () -> Void

    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "envelope.badge.shield.half.filled")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
            Text("Drop an email here to inspect it")
                .font(.title2)
                .fontWeight(.semibold)
            Text("Drag an .eml file from Finder here, or drop a message onto this app's Dock icon.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Text("Dragging directly from Apple Mail's message list onto this window isn't supported by macOS — drop it on the Dock icon instead.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            Button("Open Email File…", action: onOpenFile)
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8]))
                .foregroundStyle(isTargeted ? Color.accentColor : Color.secondary.opacity(0.4))
                .padding(24)
        )
        .contentShape(Rectangle())
        .onDrop(of: [UTType.fileURL], isTargeted: $isTargeted) { providers in
            handleDrop(providers)
            return true
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Drop an email here to inspect it. Drag an .eml file from Finder here, drop a message from Apple Mail onto this app's Dock icon, or use the Open Email File button.")
    }

    private func handleDrop(_ providers: [NSItemProvider]) {
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
            if !collected.isEmpty { onImportURLs(collected) }
        }
    }
}
