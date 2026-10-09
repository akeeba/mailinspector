//
//  Mail Inspector
//
//  Copyright (c) 2026 Nicholas K. Dionysopoulos
//  Licensed under the MIT License. See license.txt in the project root for details.
//

import Testing
import Foundation
@testable import Mail_Inspector

/// Tests for `AuthenticationResultsParser`: parsing RFC 8601 `Authentication-Results` headers
/// — authserv-id, method results and their properties, comment-derived reasons, bare `none`
/// resinfo, and preserving multiple headers from different servers separately.
@Suite("AuthenticationResultsParser")
struct AuthenticationResultsParserTests {
    @Test("Parses authserv-id and multiple method results with properties")
    func parsesBasicHeader() throws {
        let raw = "Authentication-Results: mx.google.com;\r\n" +
            " spf=pass smtp.mailfrom=sender@example.com;\r\n" +
            " dkim=pass header.d=example.com header.s=selector1;\r\n" +
            " dmarc=pass header.from=example.com\r\n\r\n"
        let message = try makeTestMessage(raw)
        let headers = AuthenticationResultsParser.parseAll(from: message.parsed)
        #expect(headers.count == 1)
        let header = headers[0]
        #expect(header.authServID == "mx.google.com")
        #expect(header.results.count == 3)
        #expect(header.results[0].method == "spf")
        #expect(header.results[0].result == "pass")
        #expect(header.results[0].property(ptype: "smtp", "mailfrom") == "sender@example.com")
        #expect(header.results[1].property(ptype: "header", "d") == "example.com")
        #expect(header.results[1].property(ptype: "header", "s") == "selector1")
    }

    @Test("Parses a comment as the reason when no explicit reason tag is present")
    func parsesCommentAsReason() throws {
        let raw = "Authentication-Results: mx.example.com; spf=softfail (sender IP not in SPF record) smtp.mailfrom=a@b.com\r\n\r\n"
        let message = try makeTestMessage(raw)
        let header = AuthenticationResultsParser.parseAll(from: message.parsed)[0]
        #expect(header.results[0].result == "softfail")
        #expect(header.results[0].reason == "sender IP not in SPF record")
    }

    @Test("Preserves multiple Authentication-Results headers from different servers separately")
    func preservesMultipleHeaders() throws {
        let raw = "Authentication-Results: mx.ourcompany.com; spf=fail smtp.mailfrom=a@evil.example\r\n" +
            "Authentication-Results: relay.someisp.net; spf=pass smtp.mailfrom=a@evil.example\r\n\r\n"
        let message = try makeTestMessage(raw)
        let headers = AuthenticationResultsParser.parseAll(from: message.parsed)
        #expect(headers.count == 2)
        #expect(headers[0].authServID == "mx.ourcompany.com")
        #expect(headers[0].results[0].result == "fail")
        #expect(headers[1].authServID == "relay.someisp.net")
        #expect(headers[1].results[0].result == "pass")
    }

    @Test("Handles a bare 'none' resinfo without crashing")
    func handlesBareNone() throws {
        let raw = "Authentication-Results: mx.example.com; none\r\n\r\n"
        let message = try makeTestMessage(raw)
        let header = AuthenticationResultsParser.parseAll(from: message.parsed)[0]
        #expect(header.results.isEmpty)
    }
}
