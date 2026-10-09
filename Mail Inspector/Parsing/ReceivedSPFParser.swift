//
//  Mail Inspector
//
//  Copyright (c) 2026 Nicholas K. Dionysopoulos
//  Licensed under the MIT License. See license.txt in the project root for details.
//

import Foundation

/// What a `Received-SPF` header recorded about the check a receiving server performed at
/// delivery time: the result, the connecting IP, and the envelope-sender domain that was
/// actually checked. This is the most direct source for re-running that same check live.
nonisolated struct ParsedReceivedSPF: Sendable {
    let result: String?
    let clientIP: String?
    let envelopeFromDomain: String?
}

nonisolated enum ReceivedSPFParser {
    static func parse(_ value: String) -> ParsedReceivedSPF {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let result = trimmed.split(separator: " ").first.map(String.init)
        let clientIP = Self.value(forKey: "client-ip", in: trimmed)
        let envelopeFrom = Self.value(forKey: "envelope-from", in: trimmed)
        let envelopeDomain = envelopeFrom.flatMap { address -> String? in
            guard let at = address.lastIndex(of: "@") else { return nil }
            let domain = String(address[address.index(after: at)...])
            return domain.isEmpty ? nil : domain
        }
        return ParsedReceivedSPF(result: result, clientIP: clientIP, envelopeFromDomain: envelopeDomain)
    }

    private static func value(forKey key: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: "\(key)=([^;\\s]+)", options: [.caseInsensitive]) else {
            return nil
        }
        let ns = text as NSString
        guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)), match.numberOfRanges > 1 else {
            return nil
        }
        var value = ns.substring(with: match.range(at: 1))
        if value.hasPrefix("<"), value.hasSuffix(">"), value.count >= 2 {
            value = String(value.dropFirst().dropLast())
        }
        return value.isEmpty ? nil : value
    }
}
