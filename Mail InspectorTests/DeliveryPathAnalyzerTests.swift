//
//  Mail Inspector
//
//  Copyright (c) 2026 Nicholas K. Dionysopoulos
//  Licensed under the MIT License. See license.txt in the project root for details.
//

import Testing
import Foundation
@testable import Mail_Inspector

/// Tests for `DeliveryPathAnalyzer`: reconstructing the oldest-to-newest hop timeline from
/// `Received` headers, flagging chronological inconsistencies and unusually long transit
/// delays, classifying private-use IPs (without over-flagging a normal leading run of internal
/// relay hops), and marking the trusted suffix of hops based on configured trusted servers.
@Suite("DeliveryPathAnalyzer")
struct DeliveryPathAnalyzerTests {
    @Test("Orders hops oldest to newest, reversing the header's newest-first order")
    func ordersHopsOldestToNewest() throws {
        let raw = "Received: from hop3.example by final.example; Wed, 4 Jan 2006 10:00:00 +0000\r\n" +
            "Received: from hop2.example by hop3.example; Tue, 3 Jan 2006 10:00:00 +0000\r\n" +
            "Received: from hop1.example by hop2.example; Mon, 2 Jan 2006 10:00:00 +0000\r\n\r\n"
        let message = try makeTestMessage(raw)
        let analysis = DeliveryPathAnalyzer.analyze(message: message, trustedAuthServIDs: [])
        #expect(analysis.hops.count == 3)
        #expect(analysis.hops[0].claimedFromHostname == "hop1.example")
        #expect(analysis.hops[1].claimedFromHostname == "hop2.example")
        #expect(analysis.hops[2].claimedFromHostname == "hop3.example")
    }

    @Test("Flags a hop whose timestamp is earlier than the previous hop's as chronologically inconsistent")
    func flagsChronologicalInconsistency() throws {
        let raw = "Received: from newer.example by final.example; Mon, 2 Jan 2006 00:00:00 +0000\r\n" +
            "Received: from older.example by newer.example; Wed, 4 Jan 2006 00:00:00 +0000\r\n\r\n"
        let message = try makeTestMessage(raw)
        let analysis = DeliveryPathAnalyzer.analyze(message: message, trustedAuthServIDs: [])
        #expect(analysis.hops[1].warnings.contains { $0.contains("chronologically inconsistent") })
    }

    @Test("Flags an unusually long transit delay between consecutive hops")
    func flagsLongTransitDelay() throws {
        let raw = "Received: from newer.example by final.example; Wed, 4 Jan 2006 00:00:00 +0000\r\n" +
            "Received: from older.example by newer.example; Mon, 2 Jan 2006 00:00:00 +0000\r\n\r\n"
        let message = try makeTestMessage(raw)
        let analysis = DeliveryPathAnalyzer.analyze(message: message, trustedAuthServIDs: [])
        #expect(analysis.hops[1].warnings.contains { $0.contains("unusually long") })
    }

    @Test("Does not flag a leading run of private-use hops, since that's how most SaaS senders normally relay internally before reaching the public internet")
    func doesNotFlagLeadingInternalHops() throws {
        let raw = "Received: from edge.example (edge.example [203.0.113.9]) by mx.example; Mon, 2 Jan 2006 00:02:00 +0000\r\n" +
            "Received: from aggregator.internal (aggregator.internal [10.0.0.6]) by edge.example; Mon, 2 Jan 2006 00:01:00 +0000\r\n" +
            "Received: from appserver.internal (appserver.internal [10.0.0.5]) by aggregator.internal; Mon, 2 Jan 2006 00:00:00 +0000\r\n\r\n"
        let message = try makeTestMessage(raw)
        let analysis = DeliveryPathAnalyzer.analyze(message: message, trustedAuthServIDs: [])
        #expect(analysis.hops[0].fromIPScope == .privateUse)
        #expect(analysis.hops[1].fromIPScope == .privateUse)
        #expect(analysis.hops[0].warnings.isEmpty)
        #expect(analysis.hops[1].warnings.isEmpty)
    }

    @Test("Flags a private-use sending IP address that appears after the message already reached the public internet")
    func flagsPrivateIPAfterPublicHop() throws {
        // 8.8.8.8 and 1.1.1.1 are genuinely public IPs (unlike the RFC 5737 documentation/
        // test-net ranges, which this app's own classifier correctly treats as non-public).
        let raw = "Received: from mx.example (mx.example [8.8.8.8]) by final.example; Mon, 2 Jan 2006 00:02:00 +0000\r\n" +
            "Received: from suspicious.internal (suspicious.internal [10.0.0.5]) by mx.example; Mon, 2 Jan 2006 00:01:00 +0000\r\n" +
            "Received: from first.example (first.example [1.1.1.1]) by suspicious.internal; Mon, 2 Jan 2006 00:00:00 +0000\r\n\r\n"
        let message = try makeTestMessage(raw)
        let analysis = DeliveryPathAnalyzer.analyze(message: message, trustedAuthServIDs: [])
        #expect(analysis.hops[1].fromIPScope == .privateUse)
        #expect(analysis.hops[1].warnings.contains { $0.contains("private-use") })
    }

    @Test("Marks only the trusted suffix of hops as trusted, stopping at the first non-matching hop")
    func marksTrustBoundary() throws {
        let raw = "Received: from upstream.example by mx.ourcompany.com; Wed, 4 Jan 2006 00:00:00 +0000\r\n" +
            "Received: from sender.example by relay.someisp.net; Mon, 2 Jan 2006 00:00:00 +0000\r\n\r\n"
        let message = try makeTestMessage(raw)
        let analysis = DeliveryPathAnalyzer.analyze(message: message, trustedAuthServIDs: ["mx.ourcompany.com"])
        #expect(analysis.hops[0].isTrusted == false)
        #expect(analysis.hops[1].isTrusted == true)
    }

    @Test("Leaves trust undeterminable (nil), not false, when no trusted servers are configured")
    func trustIsUndeterminableWithoutConfiguration() throws {
        let raw = "Received: from sender.example by mx.example; Mon, 2 Jan 2006 00:00:00 +0000\r\n\r\n"
        let message = try makeTestMessage(raw)
        let analysis = DeliveryPathAnalyzer.analyze(message: message, trustedAuthServIDs: [])
        #expect(analysis.hops[0].isTrusted == nil)
    }

    @Test("Reports no delivery path rather than crashing when there are no Received headers")
    func noReceivedHeaders() throws {
        let message = try makeTestMessage("From: a@b.com\r\n\r\n")
        let analysis = DeliveryPathAnalyzer.analyze(message: message, trustedAuthServIDs: [])
        #expect(analysis.hops.isEmpty)
        #expect(analysis.observations.contains { $0.title == "No delivery path" })
    }
}
