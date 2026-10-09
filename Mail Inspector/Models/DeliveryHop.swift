//
//  Mail Inspector
//
//  Copyright (c) 2026 Nicholas K. Dionysopoulos
//  Licensed under the MIT License. See license.txt in the project root for details.
//

import Foundation

/// How an IP address is classified for routing purposes (RFC 1918, RFC 4193, RFC 3927, etc).
/// A private/reserved address appearing where a public internet hop is expected is noteworthy,
/// not necessarily malicious — internal relays are completely normal within an organization.
nonisolated enum IPAddressScope: String, Sendable {
    case publicAddress
    case privateUse
    case loopback
    case linkLocal
    case uniqueLocal
    case carrierGradeNAT
    case documentationOrReserved
}

/// A single per-hop issue found while parsing or cross-referencing a hop against its neighbors.
///
/// Severity matters here specifically because most real-world delivery paths — anything sent
/// through a SaaS provider — routinely include internal hostnames, private-network IPs, and
/// hops whose reverse DNS doesn't resolve, simply because of how those providers relay mail
/// internally before it reaches the public internet. None of that is inherently suspicious, so
/// it's `.notable` ("worth knowing"), not `.warning`. Only a hop that looks actively
/// inconsistent or forged — a claimed hostname that contradicts reverse DNS, or a timestamp that
/// contradicts the hop before it — is `.warning`.
nonisolated struct DeliveryHopFlag: Sendable, Identifiable, Hashable {
    let id: Int
    let severity: ObservationSeverity
    let message: String
    /// Set only for the "claimed hostname contradicts reverse DNS" warning — lets
    /// `DeliveryPathView` offer a "Mark as Safe" action right next to this specific flag,
    /// without every other flag kind (unresolvable reverse DNS, long transit, etc.) needing to
    /// carry trust data they have no use for.
    let trustableHostnameMismatch: TrustedHostnameMismatch?

    init(id: Int, severity: ObservationSeverity, message: String, trustableHostnameMismatch: TrustedHostnameMismatch? = nil) {
        self.id = id
        self.severity = severity
        self.message = message
        self.trustableHostnameMismatch = trustableHostnameMismatch
    }
}

/// One `Received:` header, parsed into its conventional (not formally standardized) fields.
///
/// `id` orders hops oldest (first sent) to newest (most recent, closest to this app's import) —
/// the opposite of header order in the raw message, since each relay prepends its own `Received`
/// header above all earlier ones.
nonisolated struct DeliveryHop: Sendable, Identifiable {
    let id: Int
    let rawHeaderText: String

    /// The hostname as claimed by the sending side in the `from` clause (unverified — this is
    /// exactly the value a forging sender would control).
    let claimedFromHostname: String?
    /// The hostname the *receiving* server found via reverse DNS, when it recorded one — this is
    /// the parenthetical remark after the claimed name, e.g. `from claimed (verified [1.2.3.4])`.
    let verifiedFromHostname: String?
    let fromIPAddress: String?
    let fromIPScope: IPAddressScope?

    let byHostname: String?
    let withProtocol: String?
    let tlsVersion: String?
    let tlsCipher: String?

    let timestampRaw: String?
    let timestamp: Date?

    /// Per-hop issues found while parsing or cross-referencing this hop against its neighbors
    /// (malformed timestamp, chronological inconsistency, unusually long transit delay, claimed
    /// vs. verified hostname mismatch, private/loopback address, etc). Always phrased as an
    /// observation, never as proof of anything — see `DeliveryPathAnalyzer`'s documentation.
    let flags: [DeliveryHopFlag]

    /// Whether this hop is attributable to infrastructure the user has told the app to trust
    /// (see `InspectorSettings.trustedAuthServIDs`), or `nil` when that can't be determined at
    /// all (e.g. no trusted servers configured).
    let isTrusted: Bool?
}
