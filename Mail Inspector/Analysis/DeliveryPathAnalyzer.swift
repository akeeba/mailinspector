//
//  Mail Inspector
//
//  Copyright (c) 2026 Nicholas K. Dionysopoulos
//  Licensed under the MIT License. See license.txt in the project root for details.
//

import Foundation

nonisolated struct DeliveryPathAnalysis: Sendable {
    /// Oldest (first sent) to newest (closest to this app's import).
    let hops: [DeliveryHop]
    let observations: [SecurityObservation]
}

/// Reconstructs the delivery path from `Received:` headers into a chronological timeline and
/// flags noteworthy discrepancies.
///
/// `Received` headers are themselves untrusted once outside infrastructure the user has told
/// the app to trust: anyone relaying (or forging) a message can prepend an arbitrary `Received`
/// header. This never treats an inconsistency in an untrusted hop as proof of anything — it
/// surfaces it as an observation, not a verdict.
nonisolated enum DeliveryPathAnalyzer {
    /// Transit delays longer than this between consecutive hops are flagged as unusually long.
    private static let longTransitThreshold: TimeInterval = 24 * 60 * 60

    static func analyze(message: EmailMessage, trustedAuthServIDs: [String]) -> DeliveryPathAnalysis {
        // Received headers are prepended by each relay, so header order is newest-first; reverse
        // to get the chronological (oldest-first) order this app presents.
        let parsedNewestFirst = ReceivedHeaderParser.parseAll(from: message.parsed)
        let parsedOldestFirst = Array(parsedNewestFirst.reversed())

        let trust = trustBoundary(for: parsedOldestFirst, trustedAuthServIDs: trustedAuthServIDs)

        var hops: [DeliveryHop] = []
        var observations: [SecurityObservation] = []
        var nextObservationID = 0
        // A contiguous run of private/internal hops at the start of the chain — before the
        // message has reached the public internet at all — is completely ordinary: it's exactly
        // how most SaaS senders work (app server -> internal mail-sender service -> internal
        // aggregator -> the SMTP server that actually talks to the outside world). Only a hop
        // that goes *back* to a private address *after* a public one is unusual enough to flag.
        var hasSeenPublicAddress = false

        func addObservation(_ severity: ObservationSeverity, _ title: String, _ detail: String) {
            observations.append(SecurityObservation(id: nextObservationID, severity: severity, title: title, detail: detail))
            nextObservationID += 1
        }

        for (index, parsedHop) in parsedOldestFirst.enumerated() {
            var flags: [DeliveryHopFlag] = []
            var nextFlagID = 0
            func addFlag(_ severity: ObservationSeverity, _ message: String) {
                flags.append(DeliveryHopFlag(id: nextFlagID, severity: severity, message: message))
                nextFlagID += 1
            }

            // Parser-level issues (missing "from" clause, unparseable timestamp) are about the
            // header's shape, not evidence of anything — most real-world headers that trip these
            // are just unusual MTA formatting, not forgery.
            for warning in parsedHop.parseWarnings {
                addFlag(.notable, warning)
            }

            let ipScope = parsedHop.fromIPAddress.flatMap(IPAddressClassifier.classify)
            if let ipScope, ipScope != .publicAddress {
                if hasSeenPublicAddress {
                    let description = Self.describe(ipScope)
                    // A private/internal-network hop this late is routine for SaaS senders
                    // (internal relay hopping between services) — worth knowing, not alarming.
                    addFlag(.notable, "Sending address \(parsedHop.fromIPAddress ?? "") is \(description), not a public internet address — unusual this late in the chain, after the message had already reached the public internet.")
                }
            } else if ipScope == .publicAddress {
                hasSeenPublicAddress = true
            }

            if let claimed = parsedHop.claimedFromHostname, let verified = parsedHop.verifiedFromHostname,
               verified.caseInsensitiveCompare("unknown") != .orderedSame,
               claimed.caseInsensitiveCompare(verified) != .orderedSame,
               !claimed.contains(verified), !verified.contains(claimed) {
                // The claimed hostname actively contradicts what reverse DNS found — this is the
                // "obviously forged" case, a genuine warning.
                addFlag(.warning, "Claimed sending hostname \u{201c}\(claimed)\u{201d} does not match \u{201c}\(verified)\u{201d}, which the receiving server found via reverse DNS.")
            } else if parsedHop.verifiedFromHostname?.caseInsensitiveCompare("unknown") == .orderedSame {
                // An unresolvable reverse DNS lookup is extremely common for internal SaaS
                // infrastructure and tells you nothing by itself — a notice, not a warning.
                addFlag(.notable, "The receiving server could not verify the sending hostname via reverse DNS.")
            }

            if index > 0, let previousTimestamp = parsedOldestFirst[index - 1].timestamp, let timestamp = parsedHop.timestamp {
                let delta = timestamp.timeIntervalSince(previousTimestamp)
                if delta < 0 {
                    // A hop claiming to have happened before the one before it is a genuine
                    // inconsistency — on par with the forged-hostname case, a warning.
                    addFlag(.warning, "This hop's timestamp is earlier than the previous hop's, which is chronologically inconsistent.")
                } else if delta > longTransitThreshold {
                    let hours = Int(delta / 3600)
                    // Slow transit is usually queueing, retries, or greylisting — not forgery.
                    addFlag(.notable, "Transit from the previous hop took about \(hours) hours, which is unusually long.")
                }
            }

            let hop = DeliveryHop(
                id: index,
                rawHeaderText: parsedHop.rawHeaderText,
                claimedFromHostname: parsedHop.claimedFromHostname,
                verifiedFromHostname: parsedHop.verifiedFromHostname,
                fromIPAddress: parsedHop.fromIPAddress,
                fromIPScope: ipScope,
                byHostname: parsedHop.byHostname,
                withProtocol: parsedHop.withProtocol,
                tlsVersion: parsedHop.tlsVersion,
                tlsCipher: parsedHop.tlsCipher,
                timestampRaw: parsedHop.timestampRaw,
                timestamp: parsedHop.timestamp,
                flags: flags,
                isTrusted: trust[index]
            )
            hops.append(hop)

            let hopLabel = parsedHop.claimedFromHostname ?? parsedHop.fromIPAddress ?? "Hop \(index + 1)"
            for flag in flags {
                addObservation(flag.severity, "Delivery hop: \(hopLabel)", flag.message)
            }
        }

        if hops.isEmpty {
            addObservation(.notable, "No delivery path", "This message has no Received headers, so its delivery path cannot be reconstructed.")
        }

        return DeliveryPathAnalysis(hops: hops, observations: observations)
    }

    /// Walks from the newest hop backward, marking hops trusted while their `by` hostname
    /// matches a trusted `authserv-id`; stops at the first non-match. When no trusted servers
    /// are configured at all, trust is simply undeterminable for every hop (`nil`), not `false`.
    private static func trustBoundary(for hopsOldestFirst: [ParsedReceivedHeader], trustedAuthServIDs: [String]) -> [Bool?] {
        guard !trustedAuthServIDs.isEmpty else {
            return Array(repeating: nil, count: hopsOldestFirst.count)
        }
        let trusted = trustedAuthServIDs.map { $0.lowercased() }
        var result = Array<Bool?>(repeating: false, count: hopsOldestFirst.count)
        var stillTrusted = true
        for index in stride(from: hopsOldestFirst.count - 1, through: 0, by: -1) {
            if stillTrusted, let by = hopsOldestFirst[index].byHostname?.lowercased(),
               trusted.contains(where: { by == $0 || by.hasSuffix(".\($0)") }) {
                result[index] = true
            } else {
                stillTrusted = false
                result[index] = false
            }
        }
        return result
    }

    private static func describe(_ scope: IPAddressScope) -> String {
        switch scope {
        case .publicAddress: return "a public internet address"
        case .privateUse: return "a private-use address (RFC 1918)"
        case .loopback: return "a loopback address"
        case .linkLocal: return "a link-local address"
        case .uniqueLocal: return "a unique local address (RFC 4193)"
        case .carrierGradeNAT: return "a carrier-grade NAT address (RFC 6598)"
        case .documentationOrReserved: return "a reserved or documentation-only address"
        }
    }
}
