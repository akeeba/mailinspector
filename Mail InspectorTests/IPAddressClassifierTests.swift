//
//  Mail Inspector
//
//  Copyright (c) 2026 Nicholas K. Dionysopoulos
//  Licensed under the MIT License. See license.txt in the project root for details.
//

import Testing
import Foundation
@testable import Mail_Inspector

/// Tests for `IPAddressClassifier`: classifying IPv4/IPv6 addresses into scopes (private-use,
/// loopback, link-local, carrier-grade NAT, unique-local, documentation/reserved, public), and
/// returning nil for text that isn't a valid IP address.
@Suite("IPAddressClassifier")
struct IPAddressClassifierTests {
    @Test("Classifies common IPv4 scopes")
    func ipv4Scopes() {
        #expect(IPAddressClassifier.classify("192.168.1.1") == .privateUse)
        #expect(IPAddressClassifier.classify("10.0.0.1") == .privateUse)
        #expect(IPAddressClassifier.classify("172.16.0.1") == .privateUse)
        #expect(IPAddressClassifier.classify("127.0.0.1") == .loopback)
        #expect(IPAddressClassifier.classify("169.254.1.1") == .linkLocal)
        #expect(IPAddressClassifier.classify("100.64.0.1") == .carrierGradeNAT)
        #expect(IPAddressClassifier.classify("8.8.8.8") == .publicAddress)
    }

    @Test("Classifies common IPv6 scopes")
    func ipv6Scopes() {
        #expect(IPAddressClassifier.classify("::1") == .loopback)
        #expect(IPAddressClassifier.classify("fe80::1") == .linkLocal)
        #expect(IPAddressClassifier.classify("fd00::1") == .uniqueLocal)
        #expect(IPAddressClassifier.classify("2001:db8::1") == .documentationOrReserved)
        #expect(IPAddressClassifier.classify("2607:f8b0::1") == .publicAddress)
    }

    @Test("Returns nil for text that isn't a valid IP address")
    func invalidAddress() {
        #expect(IPAddressClassifier.classify("not-an-ip") == nil)
    }
}
