import Foundation
import Network

nonisolated enum SPFResult: String, Sendable {
    case pass, fail, softfail, neutral
    case none
    case temperror, permerror
}

nonisolated struct SPFCheckResult: Sendable {
    let result: SPFResult
    let explanation: String
    let checkedDomain: String
    let checkedIP: String
}

/// Evaluates an SPF record **right now**, independent of whatever any mail server reported in
/// Authentication-Results/Received-SPF headers.
///
/// This is fundamentally different from everything else in the Authentication analysis: SPF
/// records can change at any time, so this tells you nothing about whether the check would have
/// passed when the message was actually sent. A **fail here proves nothing** — the record may
/// have been tightened, loosened, or moved since then. A **pass is a reasonably strong, though
/// not certain, signal** — it means the IP that reportedly sent this message is, right now,
/// authorized by the domain's own published policy.
///
/// Bounded per RFC 7208 §4.6.4: at most 10 DNS lookups total (across nested `include`/`a`/`mx`),
/// and at most 10 levels of `include`/`redirect` nesting, to avoid both abuse amplification and
/// runaway recursion. `mx` mechanisms degrade gracefully (treated as non-matching, not an error)
/// when the DNS response uses name compression for the exchange hostname — compression pointers
/// reference the full DNS message, which the lower-level per-record API this app uses does not
/// expose, so they can't always be decoded.
nonisolated enum SPFEvaluator {
    private static let maxDNSLookups = 10
    private static let maxRecursionDepth = 10

    static func evaluate(ip: String, senderDomain: String) async -> SPFCheckResult {
        let budget = LookupBudget(maxDNSLookups)
        return await checkHost(domain: senderDomain, ip: ip, budget: budget, depth: 0)
    }

    private final class LookupBudget {
        private var remaining: Int
        init(_ n: Int) { remaining = n }
        func consume() -> Bool {
            guard remaining > 0 else { return false }
            remaining -= 1
            return true
        }
    }

    private static func checkHost(domain: String, ip: String, budget: LookupBudget, depth: Int) async -> SPFCheckResult {
        guard depth <= maxRecursionDepth else {
            return SPFCheckResult(result: .permerror, explanation: "Too many nested include/redirect mechanisms.", checkedDomain: domain, checkedIP: ip)
        }
        guard budget.consume() else {
            return SPFCheckResult(result: .permerror, explanation: "Exceeded the 10 DNS lookups RFC 7208 allows for one SPF evaluation.", checkedDomain: domain, checkedIP: ip)
        }

        let txtRecords: [String]
        do {
            let answers = try await DNSResolver.queryRaw(domain, type: .txt, timeoutSeconds: 5)
            txtRecords = answers.map(DNSResolver.decodeTXT).filter { $0.lowercased().hasPrefix("v=spf1") }
        } catch {
            return SPFCheckResult(result: .temperror, explanation: "Could not look up the TXT record for \(domain): \(error)", checkedDomain: domain, checkedIP: ip)
        }

        guard !txtRecords.isEmpty else {
            return SPFCheckResult(result: .none, explanation: "\(domain) publishes no SPF record.", checkedDomain: domain, checkedIP: ip)
        }
        guard txtRecords.count == 1 else {
            return SPFCheckResult(result: .permerror, explanation: "\(domain) publishes more than one SPF record, which RFC 7208 treats as a permanent error.", checkedDomain: domain, checkedIP: ip)
        }

        let terms = txtRecords[0].split(separator: " ").map(String.init).filter { !$0.isEmpty }
        var redirectDomain: String?

        for term in terms.dropFirst() where !term.isEmpty {
            let (qualifier, mechanism) = splitQualifier(term)

            if mechanism.hasPrefix("redirect=") {
                redirectDomain = String(mechanism.dropFirst("redirect=".count))
                continue
            }
            if mechanism.hasPrefix("exp=") || mechanism.contains("%{") {
                continue // Explanation modifier, or a macro this app doesn't expand.
            }
            if mechanism == "all" {
                return result(for: qualifier, mechanism: term, domain: domain, ip: ip)
            }
            if mechanism.hasPrefix("ip4:") || mechanism.hasPrefix("ip6:") {
                let cidr = String(mechanism.dropFirst(4))
                if ipMatches(ip: ip, cidr: cidr) {
                    return result(for: qualifier, mechanism: term, domain: domain, ip: ip)
                }
                continue
            }
            if mechanism.hasPrefix("include:") {
                let includedDomain = String(mechanism.dropFirst("include:".count))
                let included = await checkHost(domain: includedDomain, ip: ip, budget: budget, depth: depth + 1)
                if included.result == .pass {
                    return result(for: qualifier, mechanism: term, domain: domain, ip: ip)
                }
                if included.result == .temperror || included.result == .permerror {
                    return included
                }
                continue
            }
            if mechanism == "a" || mechanism.hasPrefix("a:") || mechanism.hasPrefix("a/") {
                if await matchesA(mechanism: mechanism, domain: domain, ip: ip, budget: budget) {
                    return result(for: qualifier, mechanism: term, domain: domain, ip: ip)
                }
                continue
            }
            if mechanism == "mx" || mechanism.hasPrefix("mx:") || mechanism.hasPrefix("mx/") {
                if await matchesMX(mechanism: mechanism, domain: domain, ip: ip, budget: budget) {
                    return result(for: qualifier, mechanism: term, domain: domain, ip: ip)
                }
                continue
            }
            // "ptr", "exists", and anything else unrecognized: not supported, never matches.
        }

        if let redirectDomain {
            return await checkHost(domain: redirectDomain, ip: ip, budget: budget, depth: depth + 1)
        }

        return SPFCheckResult(result: .neutral, explanation: "No mechanism in \(domain)'s SPF record matched \(ip), and the record has no final \"all\".", checkedDomain: domain, checkedIP: ip)
    }

    private static func splitQualifier(_ term: String) -> (qualifier: Character, mechanism: String) {
        guard let first = term.first, "+-~?".contains(first) else { return ("+", term) }
        return (first, String(term.dropFirst()))
    }

    private static func result(for qualifier: Character, mechanism: String, domain: String, ip: String) -> SPFCheckResult {
        let resolved: SPFResult
        switch qualifier {
        case "-": resolved = .fail
        case "~": resolved = .softfail
        case "?": resolved = .neutral
        default: resolved = .pass
        }
        return SPFCheckResult(result: resolved, explanation: "Matched \"\(mechanism)\" in \(domain)'s SPF record.", checkedDomain: domain, checkedIP: ip)
    }

    // MARK: - ip4/ip6 CIDR matching

    private static func ipMatches(ip: String, cidr: String) -> Bool {
        let parts = cidr.split(separator: "/", maxSplits: 1)
        guard !parts.isEmpty else { return false }
        let networkAddress = String(parts[0])
        let prefixLength = parts.count > 1 ? Int(parts[1]) : nil

        if let target = IPv4Address(ip), let network = IPv4Address(networkAddress) {
            return matchesPrefix(target.rawValue, network.rawValue, bits: prefixLength ?? 32)
        }
        if let target = IPv6Address(ip), let network = IPv6Address(networkAddress) {
            return matchesPrefix(target.rawValue, network.rawValue, bits: prefixLength ?? 128)
        }
        return false
    }

    private static func matchesPrefix(_ a: Data, _ b: Data, bits: Int) -> Bool {
        guard a.count == b.count, bits >= 0, bits <= a.count * 8 else { return false }
        let fullBytes = bits / 8
        let remainingBits = bits % 8
        if fullBytes > 0, a.prefix(fullBytes) != b.prefix(fullBytes) { return false }
        if remainingBits > 0 {
            let mask = UInt8(0xFF << (8 - remainingBits))
            let aByte = a[a.startIndex + fullBytes]
            let bByte = b[b.startIndex + fullBytes]
            if (aByte & mask) != (bByte & mask) { return false }
        }
        return true
    }

    // MARK: - "a" and "mx" mechanisms

    private static func parseDomainAndCIDR(from mechanism: String, prefixLength: Int, defaultDomain: String) -> (domain: String, cidrBits: Int?) {
        var remainder = String(mechanism.dropFirst(prefixLength))
        var domain = defaultDomain
        if remainder.hasPrefix(":") {
            remainder.removeFirst()
            if let slashIndex = remainder.firstIndex(of: "/") {
                domain = String(remainder[remainder.startIndex..<slashIndex])
                remainder = String(remainder[slashIndex...])
            } else {
                domain = remainder
                remainder = ""
            }
        }
        var cidrBits: Int?
        if remainder.hasPrefix("/") {
            let bitsText = remainder.dropFirst().split(separator: "/").first.map(String.init) ?? ""
            cidrBits = Int(bitsText)
        }
        return (domain, cidrBits)
    }

    private static func matchesA(mechanism: String, domain: String, ip: String, budget: LookupBudget) async -> Bool {
        guard budget.consume() else { return false }
        let (target, cidrBits) = parseDomainAndCIDR(from: mechanism, prefixLength: 1, defaultDomain: domain)
        let isV6 = IPv6Address(ip) != nil
        let addresses = await resolveAddresses(for: target, preferIPv6: isV6)
        let bits = cidrBits ?? (isV6 ? 128 : 32)
        return addresses.contains { ipMatches(ip: ip, cidr: "\($0)/\(bits)") }
    }

    private static func matchesMX(mechanism: String, domain: String, ip: String, budget: LookupBudget) async -> Bool {
        guard budget.consume() else { return false }
        let (target, cidrBits) = parseDomainAndCIDR(from: mechanism, prefixLength: 2, defaultDomain: domain)
        guard let mxAnswers = try? await DNSResolver.queryRaw(target, type: .mx, timeoutSeconds: 5) else { return false }

        let exchanges = mxAnswers.compactMap(decodeMXExchange).prefix(10)
        let isV6 = IPv6Address(ip) != nil
        let bits = cidrBits ?? (isV6 ? 128 : 32)
        for exchange in exchanges {
            guard budget.consume() else { return false }
            let addresses = await resolveAddresses(for: exchange, preferIPv6: isV6)
            if addresses.contains(where: { ipMatches(ip: ip, cidr: "\($0)/\(bits)") }) {
                return true
            }
        }
        return false
    }

    private static func resolveAddresses(for domain: String, preferIPv6: Bool) async -> [String] {
        let type: DNSResolver.DNSRecordType = preferIPv6 ? .aaaa : .a
        guard let answers = try? await DNSResolver.queryRaw(domain, type: type, timeoutSeconds: 5) else { return [] }
        return answers.compactMap { data in
            if type == .a, data.count == 4 {
                return data.map { String($0) }.joined(separator: ".")
            }
            if type == .aaaa, data.count == 16 {
                return IPv6Address(data).map { "\($0)" }
            }
            return nil
        }
    }

    /// Decodes an MX record's exchange hostname from its raw rdata (2-byte preference followed
    /// by the hostname). Returns `nil` if the hostname uses DNS name compression, which can't be
    /// resolved from an isolated record's rdata alone.
    private static func decodeMXExchange(_ data: Data) -> String? {
        guard data.count > 2 else { return nil }
        var labels: [String] = []
        var index = data.index(data.startIndex, offsetBy: 2)
        while index < data.endIndex {
            let length = Int(data[index])
            if length == 0 { break }
            if length & 0xC0 == 0xC0 { return nil }
            index = data.index(after: index)
            guard index + length <= data.endIndex else { return nil }
            let labelData = data[index..<data.index(index, offsetBy: length)]
            labels.append(String(decoding: labelData, as: UTF8.self))
            index = data.index(index, offsetBy: length)
        }
        return labels.isEmpty ? nil : labels.joined(separator: ".")
    }
}
