//
//  Mail Inspector
//
//  Copyright (c) 2026 Nicholas K. Dionysopoulos
//  Licensed under the MIT License. See license.txt in the project root for details.
//

import SwiftUI
import AppKit

/// Section A: sender identity, as asserted by the message itself (no authentication claims).
struct SenderIdentityView: View {
    let message: EmailMessage

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sender Identity")
                .font(.headline)

            if let from = message.primaryFrom {
                VStack(alignment: .leading, spacing: 4) {
                    if let displayName = from.displayName, !displayName.isEmpty {
                        Text(displayName)
                            .font(.title3)
                    }
                    HStack {
                        Text(from.address)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                        Button {
                            copy(from.address)
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Copy sender address")
                    }
                }
            } else {
                Text("No valid From address could be parsed.")
                    .foregroundStyle(.secondary)
            }

            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 6) {
                if let sender = message.senderAddress {
                    detailRow("Sender", sender.address)
                }
                if !message.replyToEntries.isEmpty {
                    detailRow("Reply-To", addressSummary(message.replyToEntries))
                }
                if let returnPath = message.returnPath {
                    detailRow("Return-Path", returnPath)
                }
                if !message.toEntries.isEmpty {
                    detailRow("To", addressSummary(message.toEntries))
                }
                if !message.ccEntries.isEmpty {
                    detailRow("Cc", addressSummary(message.ccEntries))
                }
                if let messageID = message.messageID {
                    detailRow("Message-ID", messageID)
                }
                if let date = message.date {
                    detailRow("Date", date.formatted(date: .abbreviated, time: .standard))
                } else if let raw = message.dateHeaderRaw {
                    detailRow("Date (unparsed)", raw)
                }
            }
        }
    }

    @ViewBuilder
    private func detailRow(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
                .gridColumnAlignment(.trailing)
            Text(value)
                .textSelection(.enabled)
                .font(.system(.body, design: .monospaced))
        }
    }

    private func addressSummary(_ entries: [AddressListEntry]) -> String {
        entries.map { entry in
            switch entry {
            case .mailbox(let address):
                return address.address
            case .group(let name, let members):
                return "\(name): \(members.map(\.address).joined(separator: ", "))"
            case .malformed(let raw):
                return "⚠︎ \(raw)"
            }
        }.joined(separator: ", ")
    }

    private func copy(_ string: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
    }
}
