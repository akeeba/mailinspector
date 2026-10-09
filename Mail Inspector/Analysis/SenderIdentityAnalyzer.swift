//
//  Mail Inspector
//
//  Copyright (c) 2026 Nicholas K. Dionysopoulos
//  Licensed under the MIT License. See license.txt in the project root for details.
//

import Foundation

/// A Reply-To domain that doesn't organizationally match From, and isn't (yet) trusted for this
/// sender — exposed separately from `observations` so `SenderIdentityView` can offer a "Mark as
/// Safe" action right next to the Reply-To row itself, regardless of whether the opt-in
/// "Noteworthy Observations" panel is even enabled.
nonisolated struct ReplyToMismatch: Sendable, Equatable {
    let replyToDomain: String
    let fromDomain: String
    /// The message's own From address — trust is a property of who *sent* the message and which
    /// address they prefer replies go to, never of who happened to receive this particular copy.
    let sender: String
}

nonisolated struct SenderIdentityAnalysis: Sendable {
    let observations: [SecurityObservation]
    let replyToMismatch: ReplyToMismatch?
}

/// Detects discrepancies in the sender identity the message itself asserts — before any
/// authentication is taken into account. These are observations, not proof: a Reply-To domain
/// that differs from From is routine for many legitimate bulk senders, and an IDN domain is not
/// inherently an impersonation attempt.
nonisolated enum SenderIdentityAnalyzer {
    /// `trustedReplyToDomainsBySender` is keyed by lowercased From address, each value a list of
    /// lowercased Reply-To domains the user has explicitly marked safe for that sender (see
    /// `InspectorSettings.trustReplyToDomain(_:forSender:)`) — e.g. a vendor whose messages
    /// always route replies to a separate help-desk domain, regardless of which of the user's
    /// own addresses received this particular message.
    static func analyze(message: EmailMessage, trustedReplyToDomainsBySender: [String: [String]] = [:]) -> SenderIdentityAnalysis {
        var observations: [SecurityObservation] = []
        var nextID = 0
        func add(_ severity: ObservationSeverity, _ title: String, _ detail: String) {
            observations.append(SecurityObservation(id: nextID, severity: severity, title: title, detail: detail))
            nextID += 1
        }
        var replyToMismatch: ReplyToMismatch?

        if message.fromHeaderCount > 1 {
            add(.warning, "Multiple From headers", "This message has \(message.fromHeaderCount) From headers. A conformant message has exactly one — multiple From headers are invalid and often indicate forgery or header injection.")
        } else if message.fromHeaderCount == 0 {
            add(.warning, "Missing From header", "This message has no From header at all.")
        }

        guard let from = message.primaryFrom else { return SenderIdentityAnalysis(observations: observations, replyToMismatch: nil) }

        if let displayName = from.displayName,
           let embeddedAddress = extractEmailAddress(from: displayName),
           embeddedAddress.caseInsensitiveCompare(from.address) != .orderedSame {
            add(.warning, "Display name contains a different address", "The From display name contains \u{201c}\(embeddedAddress)\u{201d}, which differs from the actual From address \u{201c}\(from.address)\u{201d}. Showing one address while sending from another is a common impersonation technique.")
        }

        if let displayName = from.displayName, containsSuspiciousUnicode(displayName) {
            add(.notable, "Mixed-script characters in display name", "The From display name \u{201c}\(displayName)\u{201d} mixes Latin letters with characters from another script. This can be used to visually impersonate a different name.")
        }

        if from.domain.lowercased().split(separator: ".").contains(where: { $0.hasPrefix("xn--") }) {
            add(.info, "Internationalized domain name", "The From domain \u{201c}\(from.domain)\u{201d} uses Punycode (IDN) encoding. This is not inherently suspicious — it's required for any domain with non-ASCII characters — but IDNs are also sometimes used to visually resemble an ASCII domain.")
        }

        if case .mailbox(let replyTo) = message.replyToEntries.first, !replyTo.domain.isEmpty {
            if DomainAlignment.align(from.domain, replyTo.domain) == .notAligned {
                let isTrusted = (trustedReplyToDomainsBySender[from.address.lowercased()] ?? [])
                    .contains { $0.caseInsensitiveCompare(replyTo.domain) == .orderedSame }
                if !isTrusted {
                    add(.notable, "Reply-To domain differs from From", "Reply-To (\u{201c}\(replyTo.domain)\u{201d}) is not organizationally related to the From domain (\u{201c}\(from.domain)\u{201d}). Replies would go somewhere other than where the message claims to be from.")
                    replyToMismatch = ReplyToMismatch(replyToDomain: replyTo.domain, fromDomain: from.domain, sender: from.address)
                }
            }
        }

        if let returnPath = message.returnPath, let returnPathDomain = domain(fromAngleAddrOrAddress: returnPath) {
            if DomainAlignment.align(from.domain, returnPathDomain) == .notAligned {
                add(.info, "Return-Path domain differs from From", "Return-Path (\u{201c}\(returnPathDomain)\u{201d}) is not organizationally related to the From domain (\u{201c}\(from.domain)\u{201d}). This is routine for many legitimate bulk-mail senders (it's where bounces go) and is not inherently suspicious on its own.")
            }
        }

        return SenderIdentityAnalysis(observations: observations, replyToMismatch: replyToMismatch)
    }

    private static func extractEmailAddress(from text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: "[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}") else { return nil }
        let ns = text as NSString
        guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return ns.substring(with: match.range)
    }

    /// A deliberately simple heuristic: Latin letters mixed with Cyrillic or Greek letters in
    /// the same display name, the classic homograph-mixing pattern (e.g. a Cyrillic "а" standing
    /// in for a Latin "a"). This is not a full Unicode-confusables implementation.
    private static func containsSuspiciousUnicode(_ text: String) -> Bool {
        var hasLatin = false
        var hasOtherScript = false
        for scalar in text.unicodeScalars {
            if scalar.value < 128 {
                if (0x41...0x5A).contains(scalar.value) || (0x61...0x7A).contains(scalar.value) {
                    hasLatin = true
                }
            } else if (0x0400...0x04FF).contains(scalar.value) || (0x0370...0x03FF).contains(scalar.value) {
                hasOtherScript = true
            }
        }
        return hasLatin && hasOtherScript
    }

    private static func domain(fromAngleAddrOrAddress text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: CharacterSet(charactersIn: "<> \t"))
        guard let at = trimmed.lastIndex(of: "@") else { return nil }
        let domainPart = String(trimmed[trimmed.index(after: at)...])
        return domainPart.isEmpty ? nil : domainPart
    }
}
