//
//  Mail Inspector
//
//  Copyright (c) 2026 Nicholas K. Dionysopoulos
//  Licensed under the MIT License. See license.txt in the project root for details.
//

import Testing
import Foundation
@testable import Mail_Inspector

/// Tests for `SenderIdentityAnalyzer`: surfacing sender-identity discrepancies as neutral
/// observations rather than accusations — forged display names, multiple From headers,
/// Reply-To/Return-Path domain mismatches, IDN/Punycode domains, and mixed-script display
/// names — and producing no observations at all for a clean message.
@Suite("SenderIdentityAnalyzer")
struct SenderIdentityAnalyzerTests {
    @Test("Flags a display name containing an address that differs from the actual From address")
    func forgedDisplayName() throws {
        let message = try makeTestMessage("From: \"support@bank.example\" <attacker@evil.example>\r\n\r\n")
        let analysis = SenderIdentityAnalyzer.analyze(message: message)
        #expect(analysis.observations.contains { $0.title == "Display name contains a different address" })
    }

    @Test("Flags multiple From headers")
    func multipleFromHeaders() throws {
        let message = try makeTestMessage("From: a@b.com\r\nFrom: c@d.com\r\n\r\n")
        let analysis = SenderIdentityAnalyzer.analyze(message: message)
        #expect(analysis.observations.contains { $0.title == "Multiple From headers" })
    }

    @Test("Flags a Reply-To domain that is not organizationally related to the From domain")
    func replyToMismatch() throws {
        let message = try makeTestMessage("From: billing@bank.example\r\nReply-To: attacker@evil.example\r\n\r\n")
        let analysis = SenderIdentityAnalyzer.analyze(message: message)
        #expect(analysis.observations.contains { $0.title == "Reply-To domain differs from From" })
    }

    @Test("Flags a Return-Path domain that is not organizationally related to the From domain, at informational severity")
    func returnPathMismatch() throws {
        let message = try makeTestMessage("From: billing@bank.example\r\nReturn-Path: <bounce@othermailer.example>\r\n\r\n")
        let analysis = SenderIdentityAnalyzer.analyze(message: message)
        let observation = analysis.observations.first { $0.title == "Return-Path domain differs from From" }
        #expect(observation != nil)
        #expect(observation?.severity == .info)
    }

    @Test("Flags a Punycode (IDN) From domain as informational, not as proof of impersonation")
    func idnDomain() throws {
        let message = try makeTestMessage("From: user@xn--mnich-kva.example\r\n\r\n")
        let analysis = SenderIdentityAnalyzer.analyze(message: message)
        let observation = analysis.observations.first { $0.title == "Internationalized domain name" }
        #expect(observation != nil)
        #expect(observation?.severity == .info)
    }

    @Test("Flags a display name mixing Latin and Cyrillic characters")
    func mixedScriptDisplayName() throws {
        // "Support" with a Cyrillic 'а' (U+0430) replacing the Latin 'a'.
        let message = try makeTestMessage("From: \"Supp\u{0430}rt\" <support@example.com>\r\n\r\n")
        let analysis = SenderIdentityAnalyzer.analyze(message: message)
        #expect(analysis.observations.contains { $0.title == "Mixed-script characters in display name" })
    }

    @Test("Exposes an actionable ReplyToMismatch naming every To/Cc recipient when the domain isn't yet trusted")
    func replyToMismatchIsActionable() throws {
        let message = try makeTestMessage("From: billing@bank.example\r\nReply-To: attacker@evil.example\r\nTo: sales@mycompany.example\r\nCc: ops@mycompany.example\r\n\r\n")
        let analysis = SenderIdentityAnalyzer.analyze(message: message)
        #expect(analysis.observations.contains { $0.title == "Reply-To domain differs from From" })
        let mismatch = try #require(analysis.replyToMismatch)
        #expect(mismatch.replyToDomain == "evil.example")
        #expect(mismatch.fromDomain == "bank.example")
        #expect(Set(mismatch.recipients) == Set(["sales@mycompany.example", "ops@mycompany.example"]))
    }

    @Test("Suppresses the Reply-To mismatch entirely once the domain is trusted for a recipient of the message")
    func trustedReplyToDomainSuppressesTheMismatch() throws {
        let message = try makeTestMessage("From: billing@bank.example\r\nReply-To: attacker@evil.example\r\nTo: sales@mycompany.example\r\n\r\n")
        let analysis = SenderIdentityAnalyzer.analyze(
            message: message,
            trustedReplyToDomainsByRecipient: ["sales@mycompany.example": ["evil.example"]]
        )
        #expect(!analysis.observations.contains { $0.title == "Reply-To domain differs from From" })
        #expect(analysis.replyToMismatch == nil)
    }

    @Test("A clean message with no discrepancies produces no observations")
    func cleanMessageHasNoObservations() throws {
        let message = try makeTestMessage("From: \"Alice\" <alice@example.com>\r\nReply-To: alice@example.com\r\n\r\n")
        let analysis = SenderIdentityAnalyzer.analyze(message: message)
        #expect(analysis.observations.isEmpty)
    }
}
