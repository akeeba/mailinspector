//
//  Mail Inspector
//
//  Copyright (c) 2026 Nicholas K. Dionysopoulos / Akeeba Ltd
//  Licensed under the MIT License. See license.txt in the project root for details.
//

import SwiftUI
import AppKit

/// Section A: sender identity, as asserted by the message itself (no authentication claims).
struct SenderIdentityView: View {
    let message: EmailMessage
    var dmarcVerdict: AuthenticationVerdict = .unknown
    var spamAssessment: SpamLikelihoodAssessment? = nil
    var brandImagesEnabled: Bool = false
    var hideBrandImagesForMessagesWithoutSpamScore: Bool = true
    var hideBrandImagesAboveSpamThreshold: Double = 25
    var replyToMismatch: ReplyToMismatch? = nil
    var onTrustReplyToDomain: (() -> Void)? = nil

    @State private var brandImage: NSImage?

    private var shouldShowBrandImage: Bool {
        guard let domain = message.primaryFrom?.domain, !domain.isEmpty else { return false }
        return BrandImagePolicy.shouldAttempt(
            dmarcVerdict: dmarcVerdict,
            spamAssessment: spamAssessment,
            isEnabled: brandImagesEnabled,
            hideWithoutSpamScore: hideBrandImagesForMessagesWithoutSpamScore,
            hideAboveSpamThreshold: hideBrandImagesAboveSpamThreshold
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sender Identity")
                .font(.headline)

            if let from = message.primaryFrom {
                HStack(alignment: .top, spacing: (shouldShowBrandImage && brandImage != nil) ? 10 : 0) {
                    if shouldShowBrandImage {
                        BrandImageView(domain: from.domain, image: $brandImage)
                    }
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
                    if let replyToMismatch {
                        GridRow {
                            // `Color` has no intrinsic size, so left unconstrained it happily
                            // expands to fill whatever width Grid offers — which, with nothing
                            // else in this column to measure against on this row, blew up the
                            // whole label column's width and pushed every row in the Grid over.
                            // `gridCellUnsizedAxes` tells Grid to ignore this cell when sizing
                            // the column, leaving that to the real label cells (`detailRow`'s
                            // "Sender"/"Reply-To"/etc. text) as before.
                            Color.clear
                                .gridCellUnsizedAxes(.horizontal)
                            replyToMismatchBanner(replyToMismatch)
                        }
                    }
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
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func replyToMismatchBanner(_ mismatch: ReplyToMismatch) -> some View {
        HStack(spacing: 8) {
            Label("Replies would go to \u{201c}\(mismatch.replyToDomain)\u{201d}, not \u{201c}\(mismatch.fromDomain)\u{201d}", systemImage: ObservationSeverity.notable.symbolName)
                .font(.caption)
                .foregroundStyle(ObservationSeverity.notable.tintColor)
            if let onTrustReplyToDomain {
                Button("Mark as Safe", action: onTrustReplyToDomain)
                    .buttonStyle(.link)
                    .font(.caption)
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

/// Looks up and displays a sender domain's BIMI logo. Only ever instantiated once
/// `BrandImagePolicy.shouldAttempt` has already approved it — this view itself does no gating,
/// it just performs the lookup/fetch/decode and renders whatever comes back. Most domains have
/// no BIMI record at all, so `image` reports back through a binding rather than owning its own
/// state: that lets the parent collapse the space (and its leading spacing) it reserves for the
/// logo entirely, instead of leaving a permanent blank box wherever a lookup finds nothing.
private struct BrandImageView: View {
    let domain: String
    @Binding var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
        .task(id: domain) {
            image = nil
            guard let record = await BrandImageResolver.lookupRecord(domain: domain),
                  let data = await BrandImageResolver.fetchImageData(at: record.logoURL) else {
                return
            }
            image = NSImage(data: data)
        }
    }
}
