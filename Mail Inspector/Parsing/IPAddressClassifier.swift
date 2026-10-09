//
//  Mail Inspector
//
//  Copyright (c) 2026 Nicholas K. Dionysopoulos / Akeeba Ltd
//  Licensed under the MIT License. See license.txt in the project root for details.
//

import Foundation
import Network

/// Classifies an IPv4 or IPv6 address into its routing scope (RFC 1918, RFC 4193, RFC 3927,
/// RFC 6598, etc) using `Network.IPv4Address`/`IPv6Address` for parsing — no DNS, no network
/// access, just byte-level range checks against the literal address text.
nonisolated enum IPAddressClassifier {
    static func classify(_ address: String) -> IPAddressScope? {
        if let v4 = IPv4Address(address) {
            return classifyIPv4(v4.rawValue)
        }
        if let v6 = IPv6Address(address) {
            return classifyIPv6(v6.rawValue)
        }
        return nil
    }

    private static func classifyIPv4(_ bytes: Data) -> IPAddressScope {
        let b = [UInt8](bytes)
        guard b.count == 4 else { return .publicAddress }

        if b[0] == 127 { return .loopback }
        if b[0] == 10 { return .privateUse }
        if b[0] == 172, (16...31).contains(b[1]) { return .privateUse }
        if b[0] == 192, b[1] == 168 { return .privateUse }
        if b[0] == 169, b[1] == 254 { return .linkLocal }
        if b[0] == 100, (64...127).contains(b[1]) { return .carrierGradeNAT }
        if b[0] == 0 { return .documentationOrReserved }
        if b[0] == 192, b[1] == 0, b[2] == 2 { return .documentationOrReserved }
        if b[0] == 198, b[1] == 51, b[2] == 100 { return .documentationOrReserved }
        if b[0] == 203, b[1] == 0, b[2] == 113 { return .documentationOrReserved }
        if b[0] >= 240 { return .documentationOrReserved }
        return .publicAddress
    }

    private static func classifyIPv6(_ bytes: Data) -> IPAddressScope {
        let b = [UInt8](bytes)
        guard b.count == 16 else { return .publicAddress }

        if b.allSatisfy({ $0 == 0 }) { return .documentationOrReserved }
        if b[0..<15].allSatisfy({ $0 == 0 }) && b[15] == 1 { return .loopback }
        if b[0] == 0xFE, (b[1] & 0xC0) == 0x80 { return .linkLocal }
        if (b[0] & 0xFE) == 0xFC { return .uniqueLocal }
        // 2001:db8::/32 — documentation.
        if b[0] == 0x20, b[1] == 0x01, b[2] == 0x0D, b[3] == 0xB8 { return .documentationOrReserved }
        return .publicAddress
    }
}
