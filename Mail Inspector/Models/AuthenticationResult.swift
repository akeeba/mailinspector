import Foundation

/// A single `ptype.property=value` annotation attached to a method result, e.g. `smtp.mailfrom`
/// or `header.d` (RFC 8601 §2.2).
nonisolated struct AuthProperty: Sendable, Equatable {
    let ptype: String
    let property: String
    let value: String
}

/// One `method=result` entry (a "resinfo") inside an `Authentication-Results` header, e.g.
/// `spf=pass smtp.mailfrom=example.com`.
nonisolated struct AuthMethodResult: Sendable, Identifiable, Equatable {
    let id: Int
    /// Lowercased method name: "spf", "dkim", "dmarc", or any other registered/extension method.
    let method: String
    let methodVersion: String?
    /// Lowercased result keyword: "pass", "fail", "softfail", "neutral", "none", "temperror",
    /// "permerror", "policy", or any other extension keyword — preserved verbatim, not narrowed.
    let result: String
    let reason: String?
    let properties: [AuthProperty]

    func property(ptype: String, _ property: String) -> String? {
        properties.first {
            $0.ptype.caseInsensitiveCompare(ptype) == .orderedSame &&
            $0.property.caseInsensitiveCompare(property) == .orderedSame
        }?.value
    }
}

/// A single parsed `Authentication-Results` header (RFC 8601). A message may carry several —
/// one per hop, or several appended by different filtering layers at the same hop — and they
/// must never be collapsed into one, since who added which one is exactly what determines
/// whether it can be trusted.
nonisolated struct AuthenticationResultsHeader: Sendable, Identifiable {
    let id: Int
    let authServID: String
    let authServVersion: String?
    let results: [AuthMethodResult]
    /// The original header text, for the "view raw header" expansion.
    let rawHeaderText: String
}

/// A parsed `DKIM-Signature` header (RFC 6376). Describes what the signer asserts, not whether
/// the signature actually verifies — this app parses and displays, it does not verify.
nonisolated struct DKIMSignature: Sendable, Identifiable {
    let id: Int
    let version: String?
    let algorithm: String?
    let headerCanonicalization: String?
    let bodyCanonicalization: String?
    /// `d=` — the domain that signed the message.
    let signingDomain: String?
    /// `s=` — the selector used to look up the public key under the signing domain.
    let selector: String?
    /// `h=` — the ordered list of header field names that were signed.
    let signedHeaders: [String]
    /// `t=` — when the signature was generated.
    let timestamp: Date?
    /// `x=` — when the signature expires, if the signer set an expiry.
    let expiration: Date?
    /// `i=` — the identity on behalf of which the signature was created, if present.
    let identity: String?
    /// Every tag as parsed, verbatim, for the raw-header expansion and for tags not otherwise
    /// surfaced as a dedicated property (e.g. `bh=`, `b=`, `l=`, `q=`, `z=`).
    let rawTags: [String: String]
    let rawHeaderText: String
}
