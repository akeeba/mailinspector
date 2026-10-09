//
//  Mail Inspector
//
//  Copyright (c) 2026 Nicholas K. Dionysopoulos
//  Licensed under the MIT License. See license.txt in the project root for details.
//

import SwiftUI
import AppKit

/// A searchable, read-only, monospaced view of every original header field.
struct RawHeadersView: View {
    let message: EmailMessage
    @State private var searchText = ""
    @State private var isExpanded = false

    private var filteredHeaders: [HeaderField] {
        guard !searchText.isEmpty else { return message.parsed.headers }
        return message.parsed.headers.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.unfoldedValue.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 8) {
                if message.parsed.headers.isEmpty {
                    Text("This message has no headers.")
                        .foregroundStyle(.secondary)
                } else if filteredHeaders.isEmpty {
                    Text("No headers match “\(searchText)”.")
                        .foregroundStyle(.secondary)
                } else {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(filteredHeaders) { field in
                            HeaderFieldRow(field: field)
                        }
                    }
                }
            }
            .padding(.top, 6)
        } label: {
            HStack {
                Text("Raw Headers")
                    .font(.headline)
                Spacer()
                Button {
                    copyAllHeaders()
                } label: {
                    Label("Copy All", systemImage: "doc.on.doc")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Copy all headers to the clipboard")
            }
        }
        .searchable(text: $searchText, prompt: "Search headers")
    }

    private func copyAllHeaders() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(message.parsed.rawHeaderText, forType: .string)
    }
}

private struct HeaderFieldRow: View {
    let field: HeaderField

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(field.name.isEmpty ? "(no field name)" : field.name)
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(.semibold)
                Spacer()
                Button {
                    copy()
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Copy \(field.name) header")
            }
            Text(field.rawText)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .foregroundStyle(.secondary)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.08)))
    }

    private func copy() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString("\(field.name): \(field.unfoldedValue)", forType: .string)
    }
}
