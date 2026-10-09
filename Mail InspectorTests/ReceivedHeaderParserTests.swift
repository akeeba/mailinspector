//
//  Mail Inspector
//
//  Copyright (c) 2026 Nicholas K. Dionysopoulos
//  Licensed under the MIT License. See license.txt in the project root for details.
//

import Testing
import Foundation
@testable import Mail_Inspector

/// Tests for `ReceivedHeaderParser`: extracting hostname, IP, receiving host, protocol, TLS
/// info, and timestamp from a single `Received` hop, including bracketed IPv4/IPv6 literals,
/// reverse-DNS mismatches, unparseable timestamps, missing `from` clauses, and distinguishing
/// a reverse-DNS parenthetical from an unrelated second parenthetical (e.g. TLS info).
@Suite("ReceivedHeaderParser")
struct ReceivedHeaderParserTests {
    @Test("Parses hostname, IP, receiving host, protocol, TLS info, and timestamp from a well-formed hop")
    func parsesWellFormedHop() throws {
        let raw = "Received: from mail.sender.example (mail.sender.example [192.0.2.10])\r\n" +
            " by mx.recipient.example with ESMTPS id ABC123\r\n" +
            " (version=TLS1.3 cipher=AEAD-AES256-GCM-SHA384 bits=256/256)\r\n" +
            " for <bob@recipient.example>; Mon, 2 Jan 2006 15:04:05 +0000\r\n\r\n"
        let message = try makeTestMessage(raw)
        let hop = ReceivedHeaderParser.parseAll(from: message.parsed)[0]
        #expect(hop.claimedFromHostname == "mail.sender.example")
        #expect(hop.verifiedFromHostname == "mail.sender.example")
        #expect(hop.fromIPAddress == "192.0.2.10")
        #expect(hop.byHostname == "mx.recipient.example")
        #expect(hop.withProtocol?.hasPrefix("ESMTPS") == true)
        #expect(hop.tlsVersion == "TLS1.3")
        #expect(hop.tlsCipher == "AEAD-AES256-GCM-SHA384")
        #expect(hop.timestamp != nil)
        #expect(hop.parseWarnings.isEmpty)
    }

    @Test("Surfaces a claimed hostname that differs from the receiver-verified (reverse DNS) hostname")
    func claimedAndVerifiedHostnamesCanDiffer() throws {
        let raw = "Received: from totally-different.example (actual-ptr.evil.example [203.0.113.5]) by mx.recipient.example; Mon, 2 Jan 2006 15:04:05 +0000\r\n\r\n"
        let message = try makeTestMessage(raw)
        let hop = ReceivedHeaderParser.parseAll(from: message.parsed)[0]
        #expect(hop.claimedFromHostname == "totally-different.example")
        #expect(hop.verifiedFromHostname == "actual-ptr.evil.example")
    }

    @Test("Parses a bracketed IP literal with no parenthetical remark")
    func bracketedIPWithoutParenthetical() throws {
        let raw = "Received: from [10.0.0.5] by mx.recipient.example; Mon, 2 Jan 2006 15:04:05 +0000\r\n\r\n"
        let message = try makeTestMessage(raw)
        let hop = ReceivedHeaderParser.parseAll(from: message.parsed)[0]
        #expect(hop.fromIPAddress == "10.0.0.5")
    }

    @Test("Strips the IPv6: prefix from a bracketed IPv6 address")
    func ipv6BracketedAddress() throws {
        let raw = "Received: from host.example (host.example [IPv6:2001:db8::1]) by mx.recipient.example; Mon, 2 Jan 2006 15:04:05 +0000\r\n\r\n"
        let message = try makeTestMessage(raw)
        let hop = ReceivedHeaderParser.parseAll(from: message.parsed)[0]
        #expect(hop.fromIPAddress == "2001:db8::1")
    }

    @Test("Records 'unknown' as the verified hostname when reverse DNS failed")
    func unknownReverseDNS() throws {
        let raw = "Received: from mail.example.com (unknown [198.51.100.7]) by mx.recipient.example; Mon, 2 Jan 2006 15:04:05 +0000\r\n\r\n"
        let message = try makeTestMessage(raw)
        let hop = ReceivedHeaderParser.parseAll(from: message.parsed)[0]
        #expect(hop.verifiedFromHostname == "unknown")
    }

    @Test("Flags a missing 'from' clause instead of silently ignoring the malformed header")
    func missingFromClause() throws {
        let raw = "Received: by mx.recipient.example; Mon, 2 Jan 2006 15:04:05 +0000\r\n\r\n"
        let message = try makeTestMessage(raw)
        let hop = ReceivedHeaderParser.parseAll(from: message.parsed)[0]
        #expect(hop.claimedFromHostname == nil)
        #expect(hop.parseWarnings.contains { $0.contains("from") })
    }

    @Test("Flags an unparseable timestamp instead of silently ignoring it")
    func malformedTimestamp() throws {
        let raw = "Received: from a.example by b.example; not-a-date\r\n\r\n"
        let message = try makeTestMessage(raw)
        let hop = ReceivedHeaderParser.parseAll(from: message.parsed)[0]
        #expect(hop.timestamp == nil)
        #expect(hop.parseWarnings.contains { $0.contains("timestamp") })
    }

    @Test("Treats a bare IP in parentheses (Microsoft/Exchange style) as the sending IP, not a mismatched reverse-DNS hostname")
    func bareIPInParenthesesIsTheIPNotAVerifiedHostname() throws {
        let raw = "Received: from bg-d.cloudflare-smtp.com (104.30.16.3) by MAD0EPF000008C4.mail.protection.outlook.com (10.167.241.200) with Microsoft SMTP Server (version=TLS1_3, cipher=TLS_AES_256_GCM_SHA384) id 15.21.472.14 via Frontend Transport; Wed, 30 Sep 2026 11:30:36 +0000\r\n\r\n"
        let message = try makeTestMessage(raw)
        let hop = ReceivedHeaderParser.parseAll(from: message.parsed)[0]
        #expect(hop.claimedFromHostname == "bg-d.cloudflare-smtp.com")
        #expect(hop.fromIPAddress == "104.30.16.3")
        #expect(hop.verifiedFromHostname == nil)
    }

    @Test("Does not merge an unrelated second parenthetical (e.g. a TLS-info remark) into the reverse-DNS hostname")
    func secondUnrelatedParentheticalIsNotMergedIntoVerifiedHostname() throws {
        let raw = "Received: from mx2.mailbox.org ([2001:67c:2050:104:0:2:25:2])\r\n" +
            "    (using TLSv1.3 with cipher TLS_AES_256_GCM_SHA384 (256/256 bits))\r\n" +
            "    by director-20.heinlein-hosting.de with LMTPS\r\n" +
            "    id yLUPJ3mux2p02wAACwj3lQ\r\n" +
            "    (envelope-from <Hs-no.reply@e-prescription.gr>)\r\n" +
            "    for <nicholas@dionysopoulos.me>; Thu, 08 Oct 2026 16:53:45 +0200\r\n\r\n"
        let message = try makeTestMessage(raw)
        let hop = ReceivedHeaderParser.parseAll(from: message.parsed)[0]
        #expect(hop.claimedFromHostname == "mx2.mailbox.org")
        #expect(hop.fromIPAddress == "2001:67c:2050:104:0:2:25:2")
        #expect(hop.verifiedFromHostname == nil)
        #expect(hop.byHostname == "director-20.heinlein-hosting.de")
        #expect(hop.tlsVersion == "TLSv1.3")
        #expect(hop.tlsCipher == "TLS_AES_256_GCM_SHA384")
    }
}
