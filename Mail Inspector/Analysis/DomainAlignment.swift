import Foundation

/// Compares domains both exactly and at the "organizational domain" level (e.g. `mail.example.com`
/// and `example.com` are organizationally the same domain; `example.com` and `evil.example` are not).
///
/// Organizational-domain boundaries are computed from the Public Suffix List (`PublicSuffixList`),
/// not a hardcoded heuristic — domains like `ministry.gov.gr` need the real list to be resolved
/// correctly, since a plain two-label guess would treat `gov.gr` itself as the organizational
/// domain.
nonisolated enum DomainAlignment {
    enum Result: Sendable, Equatable {
        /// Identical domains.
        case strict
        /// Different domains, same organizational domain (e.g. a legitimate subdomain).
        case relaxed
        case notAligned
    }

    static func align(_ a: String, _ b: String) -> Result {
        let a = a.lowercased()
        let b = b.lowercased()
        if a == b { return .strict }
        return organizationalDomain(of: a) == organizationalDomain(of: b) ? .relaxed : .notAligned
    }

    static func organizationalDomain(of domain: String) -> String {
        PublicSuffixList.shared.organizationalDomain(of: domain)
    }
}
