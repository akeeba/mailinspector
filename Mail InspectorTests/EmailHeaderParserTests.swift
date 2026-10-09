//
//  Mail Inspector
//
//  Copyright (c) 2026 Nicholas K. Dionysopoulos
//  Licensed under the MIT License. See license.txt in the project root for details.
//

import Testing
import Foundation
@testable import Mail_Inspector

/// Tests for `EmailHeaderParser`: splitting raw RFC 5322 source into headers and body,
/// handling line-ending variants, header folding, duplicate/malformed headers, non-UTF-8
/// bytes, and message-size limits.
@Suite("EmailHeaderParser")
struct EmailHeaderParserTests {
    @Test("Splits a simple CRLF message into headers and body without touching the body")
    func basicCRLFMessage() throws {
        let raw = "From: alice@example.com\r\nTo: bob@example.com\r\nSubject: Hello\r\n\r\nThis is the body.\r\n"
        let data = Data(raw.utf8)
        let parsed = try EmailHeaderParser.parse(data: data, maxMessageSize: 1_000_000)

        #expect(parsed.headers.count == 3)
        #expect(parsed.firstHeader(named: "from")?.unfoldedValue == "alice@example.com")
        #expect(parsed.firstHeader(named: "SUBJECT")?.unfoldedValue == "Hello")
        let body = String(decoding: data.suffix(from: parsed.bodyOffset), as: UTF8.self)
        #expect(body == "This is the body.\r\n")
    }

    @Test("Handles bare LF line endings")
    func bareLFMessage() throws {
        let raw = "From: alice@example.com\nSubject: Hi\n\nBody text\n"
        let parsed = try EmailHeaderParser.parse(data: Data(raw.utf8), maxMessageSize: 1_000_000)
        #expect(parsed.firstHeader(named: "From")?.unfoldedValue == "alice@example.com")
        #expect(parsed.firstHeader(named: "Subject")?.unfoldedValue == "Hi")
    }

    @Test("Unfolds a header continued across multiple lines")
    func foldedHeader() throws {
        let raw = "Subject: This is a\r\n very long\r\n\tsubject line\r\n\r\nBody\r\n"
        let parsed = try EmailHeaderParser.parse(data: Data(raw.utf8), maxMessageSize: 1_000_000)
        let subject = parsed.firstHeader(named: "Subject")
        #expect(subject?.unfoldedValue == "This is a very long\tsubject line")
        #expect(subject?.rawText.contains("\n") == true)
    }

    @Test("Preserves repeated headers instead of discarding duplicates")
    func repeatedHeaders() throws {
        let raw = "Received: hop1\r\nReceived: hop2\r\nFrom: a@b.com\r\n\r\n"
        let parsed = try EmailHeaderParser.parse(data: Data(raw.utf8), maxMessageSize: 1_000_000)
        #expect(parsed.headers(named: "Received").count == 2)
    }

    @Test("Matches header names case-insensitively")
    func caseInsensitiveNames() throws {
        let raw = "FROM: a@b.com\r\n\r\n"
        let parsed = try EmailHeaderParser.parse(data: Data(raw.utf8), maxMessageSize: 1_000_000)
        #expect(parsed.firstHeader(named: "from") != nil)
        #expect(parsed.firstHeader(named: "From") != nil)
    }

    @Test("Records a warning and keeps going when no header/body separator exists")
    func missingBodySeparator() throws {
        let raw = "From: a@b.com\r\nSubject: no body separator"
        let parsed = try EmailHeaderParser.parse(data: Data(raw.utf8), maxMessageSize: 1_000_000)
        #expect(!parsed.warnings.isEmpty)
        #expect(parsed.firstHeader(named: "From")?.unfoldedValue == "a@b.com")
    }

    @Test("Preserves a header line with no colon as a malformed field rather than discarding it")
    func headerLineWithoutColon() throws {
        let raw = "From: a@b.com\r\nThis line has no colon\r\nSubject: Hi\r\n\r\nBody\r\n"
        let parsed = try EmailHeaderParser.parse(data: Data(raw.utf8), maxMessageSize: 1_000_000)
        #expect(parsed.headers.contains { $0.rawText == "This line has no colon" })
        #expect(parsed.firstHeader(named: "Subject")?.unfoldedValue == "Hi")
    }

    @Test("Flags a folded continuation line with no preceding header field as malformed, without crashing or misattributing it")
    func malformedFoldingOrphanContinuation() throws {
        // The leading-whitespace line right after the blank header/body separator looks like a
        // fold continuation, but there's no header left to fold into — the body has already
        // started. A line with leading whitespace appearing *before* any header exercises the
        // genuinely malformed case this warning exists for.
        let raw = " Orphaned continuation with no preceding header\r\nFrom: a@b.com\r\nSubject: Hi\r\n\r\nBody\r\n"
        let parsed = try EmailHeaderParser.parse(data: Data(raw.utf8), maxMessageSize: 1_000_000)
        #expect(parsed.warnings.contains { $0.contains("folded continuation") })
        #expect(parsed.firstHeader(named: "From")?.unfoldedValue == "a@b.com")
        #expect(parsed.firstHeader(named: "Subject")?.unfoldedValue == "Hi")
    }

    @Test("Falls back to Latin-1 for non-UTF-8 header bytes instead of failing")
    func nonUTF8Bytes() throws {
        var bytes = Array("Subject: ".utf8)
        bytes.append(0xE9) // invalid standalone UTF-8 continuation byte
        bytes.append(contentsOf: Array("\r\n\r\n".utf8))
        let parsed = try EmailHeaderParser.parse(data: Data(bytes), maxMessageSize: 1_000_000)
        #expect(parsed.firstHeader(named: "Subject") != nil)
    }

    @Test("Rejects a message larger than the configured maximum size")
    func messageTooLarge() {
        let raw = Data(repeating: 0x41, count: 100)
        #expect(throws: EmailParsingError.self) {
            try EmailHeaderParser.parse(data: raw, maxMessageSize: 10)
        }
    }

    @Test("Rejects empty input")
    func emptyInput() {
        #expect(throws: EmailParsingError.self) {
            try EmailHeaderParser.parse(data: Data(), maxMessageSize: 1_000_000)
        }
    }

    @Test("Handles an unusually large but within-limit message without crashing")
    func largeMessage() throws {
        let filler = String(repeating: "X", count: 500_000)
        let raw = "From: a@b.com\r\nSubject: \(filler)\r\n\r\nBody\r\n"
        let parsed = try EmailHeaderParser.parse(data: Data(raw.utf8), maxMessageSize: 10_000_000)
        #expect(parsed.firstHeader(named: "Subject")?.unfoldedValue.count == filler.count)
    }
}
