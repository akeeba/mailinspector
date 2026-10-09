//
//  Mail Inspector
//
//  Copyright (c) 2026 Nicholas K. Dionysopoulos / Akeeba Ltd
//  Licensed under the MIT License. See license.txt in the project root for details.
//

import Foundation

/// An imported, parsed email message. Carries the parsed headers plus convenience accessors
/// for the fields the UI needs; never decodes or exposes the MIME body.
nonisolated struct EmailMessage: Sendable, Identifiable {
    let id = UUID()
    let parsed: ParsedEmail
    /// A human-readable origin for the sidebar (e.g. a filename). Never message content.
    let sourceDescription: String
    let importedAt: Date

    init(parsed: ParsedEmail, sourceDescription: String, importedAt: Date = Date()) {
        self.parsed = parsed
        self.sourceDescription = sourceDescription
        self.importedAt = importedAt
    }

    var subject: String? {
        parsed.firstHeader(named: "Subject").map { RFC2047Decoder.decode($0.unfoldedValue) }
    }

    var fromHeaderCount: Int { parsed.headers(named: "From").count }

    var fromEntries: [AddressListEntry] {
        parsed.headers(named: "From").flatMap { AddressParser.parseAddressList($0.unfoldedValue) }
    }

    /// The first mailbox found in `From`, which is what should be shown as "the" sender.
    /// A `fromHeaderCount` greater than 1, or multiple mailboxes in a single header, are
    /// themselves noteworthy and are surfaced separately rather than hidden here.
    var primaryFrom: EmailAddress? {
        for entry in fromEntries {
            switch entry {
            case .mailbox(let address): return address
            case .group(_, let members): if let first = members.first { return first }
            case .malformed: continue
            }
        }
        return nil
    }

    var senderAddress: EmailAddress? {
        parsed.firstHeader(named: "Sender").flatMap { AddressParser.parseMailbox($0.unfoldedValue) }
    }

    var replyToEntries: [AddressListEntry] {
        parsed.headers(named: "Reply-To").flatMap { AddressParser.parseAddressList($0.unfoldedValue) }
    }

    var toEntries: [AddressListEntry] {
        parsed.headers(named: "To").flatMap { AddressParser.parseAddressList($0.unfoldedValue) }
    }

    var ccEntries: [AddressListEntry] {
        parsed.headers(named: "Cc").flatMap { AddressParser.parseAddressList($0.unfoldedValue) }
    }

    var returnPath: String? {
        parsed.firstHeader(named: "Return-Path")?.unfoldedValue.trimmingCharacters(in: .whitespaces)
    }

    var messageID: String? {
        parsed.firstHeader(named: "Message-ID")?.unfoldedValue.trimmingCharacters(in: .whitespaces)
    }

    var dateHeaderRaw: String? {
        parsed.firstHeader(named: "Date")?.unfoldedValue
    }

    var date: Date? {
        dateHeaderRaw.flatMap { EmailDateParser.parse($0) }
    }
}
