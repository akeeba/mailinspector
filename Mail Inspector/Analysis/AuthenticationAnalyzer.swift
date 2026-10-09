import Foundation

/// How an authentication result should be presented. Never implies overall message safety —
/// a `.pass` here means only that the named method passed, nothing about the message as a whole.
nonisolated enum AuthenticationVerdict: String, Sendable {
    case pass
    case fail
    case warning
    case unverified
    case unknown
}

/// One method result (`AuthMethodResult`) together with which `Authentication-Results` header
/// it came from and whether that header's `authserv-id` is in the user's trusted list.
///
/// Matching a trusted `authserv-id` string is itself not proof of authenticity — if upstream
/// relays can inject arbitrary `Authentication-Results` headers before the message reaches the
/// receiving server, the receiving infrastructure must strip or disregard any such header that
/// didn't genuinely come from itself. This app has no way to verify that server-side behavior;
/// `isTrusted` reflects either that the `authserv-id` string matches something the user
/// explicitly configured in Settings, or that `trustAllAuthenticationResultsByDefault` is on
/// (the default) and every report is treated as trusted. Neither is proof of authenticity. That
/// caveat is why even "trusted" results are never shown with an unqualified "Pass" — see
/// `AuthenticationView`.
nonisolated struct AttributedAuthResult: Sendable, Identifiable {
    let id: Int
    let authServID: String
    let result: AuthMethodResult
    let isTrusted: Bool
}

/// The aggregated status of one method (SPF, DKIM, or DMARC) across every
/// `Authentication-Results` header on the message.
nonisolated struct MethodAuthenticationSummary: Sendable, Identifiable {
    let id: String
    let displayName: String
    let verdict: AuthenticationVerdict
    let attributedResults: [AttributedAuthResult]

    var trustedResults: [AttributedAuthResult] { attributedResults.filter(\.isTrusted) }
    var unverifiedResults: [AttributedAuthResult] { attributedResults.filter { !$0.isTrusted } }
}

/// DMARC-style alignment between the RFC5322.From domain and the domains SPF/DKIM actually
/// authenticated, computed only from trusted reports (alignment computed from an unverified
/// report would be meaningless — it could name any domain).
nonisolated struct DMARCAlignmentAnalysis: Sendable {
    let fromDomain: String?
    let spfAlignment: DomainAlignment.Result?
    let spfCheckedDomain: String?
    let dkimAlignment: DomainAlignment.Result?
    let dkimSigningDomain: String?
}

nonisolated struct AuthenticationAnalysis: Sendable {
    let authenticationResultsHeaders: [AuthenticationResultsHeader]
    let dkimSignatures: [DKIMSignature]
    let spf: MethodAuthenticationSummary
    let dkim: MethodAuthenticationSummary
    let dmarc: MethodAuthenticationSummary
    let alignment: DMARCAlignmentAnalysis
}

/// Builds the authentication summary for a message.
///
/// **This only parses and reports results other servers already computed and wrote into the
/// message's headers — it never independently performs SPF, DKIM, or DMARC verification itself**
/// (no DNS queries, no signature cryptography). A "Pass" anywhere in this analysis means "a
/// server reported a pass", not "this app independently verified a pass".
nonisolated enum AuthenticationAnalyzer {
    static func analyze(
        message: EmailMessage,
        trustedAuthServIDs: [String],
        trustAllByDefault: Bool = false
    ) -> AuthenticationAnalysis {
        let headers = AuthenticationResultsParser.parseAll(from: message.parsed)
        let dkimSignatures = DKIMSignatureParser.parseAll(from: message.parsed)
        let trusted = Set(trustedAuthServIDs.map { $0.lowercased() })

        func attributedResults(forMethod method: String) -> [AttributedAuthResult] {
            var items: [AttributedAuthResult] = []
            var nextID = 0
            for header in headers {
                let isTrusted = trustAllByDefault || trusted.contains(header.authServID.lowercased())
                for result in header.results where result.method == method {
                    items.append(AttributedAuthResult(id: nextID, authServID: header.authServID, result: result, isTrusted: isTrusted))
                    nextID += 1
                }
            }
            return items
        }

        func summary(method: String, displayName: String) -> MethodAuthenticationSummary {
            let results = attributedResults(forMethod: method)
            let trustedResults = results.filter(\.isTrusted)
            let verdict: AuthenticationVerdict = trustedResults.isEmpty
                ? .unknown
                : worstVerdict(of: trustedResults.map { verdict(forRawResult: $0.result.result) })
            return MethodAuthenticationSummary(id: method, displayName: displayName, verdict: verdict, attributedResults: results)
        }

        let spf = summary(method: "spf", displayName: "SPF")
        let dkim = summary(method: "dkim", displayName: "DKIM")
        let dmarc = summary(method: "dmarc", displayName: "DMARC")

        let fromDomain = message.primaryFrom?.domain
        let alignment = computeAlignment(fromDomain: fromDomain, spf: spf, dkim: dkim)

        return AuthenticationAnalysis(
            authenticationResultsHeaders: headers,
            dkimSignatures: dkimSignatures,
            spf: spf,
            dkim: dkim,
            dmarc: dmarc,
            alignment: alignment
        )
    }

    private static func computeAlignment(
        fromDomain: String?,
        spf: MethodAuthenticationSummary,
        dkim: MethodAuthenticationSummary
    ) -> DMARCAlignmentAnalysis {
        guard let fromDomain, !fromDomain.isEmpty else {
            return DMARCAlignmentAnalysis(fromDomain: nil, spfAlignment: nil, spfCheckedDomain: nil, dkimAlignment: nil, dkimSigningDomain: nil)
        }

        // Alignment is only meaningful against a trusted, passing report — an unverified or
        // failing report's claimed domain proves nothing about what was actually checked.
        let spfDomain = spf.trustedResults.first { $0.result.result == "pass" }
            .flatMap { $0.result.property(ptype: "smtp", "mailfrom") ?? $0.result.property(ptype: "smtp", "helo") }
            .flatMap(Self.domain(fromAddressOrHost:))
        let dkimDomain = dkim.trustedResults.first { $0.result.result == "pass" }
            .flatMap { $0.result.property(ptype: "header", "d") }

        return DMARCAlignmentAnalysis(
            fromDomain: fromDomain,
            spfAlignment: spfDomain.map { DomainAlignment.align(fromDomain, $0) },
            spfCheckedDomain: spfDomain,
            dkimAlignment: dkimDomain.map { DomainAlignment.align(fromDomain, $0) },
            dkimSigningDomain: dkimDomain
        )
    }

    /// `smtp.mailfrom` is an address (`user@domain`); `smtp.helo` is a bare hostname. Accept both.
    private static func domain(fromAddressOrHost value: String) -> String? {
        if let at = value.lastIndex(of: "@") {
            let domain = String(value[value.index(after: at)...])
            return domain.isEmpty ? nil : domain
        }
        return value.isEmpty ? nil : value
    }

    private static func verdict(forRawResult result: String) -> AuthenticationVerdict {
        switch result {
        case "pass": return .pass
        case "fail": return .fail
        case "softfail", "neutral", "policy", "none", "temperror", "permerror": return .warning
        default: return .warning
        }
    }

    /// When several trusted headers disagree (rare, but possible with multiple filtering
    /// layers), surface the most alarming verdict rather than averaging them away.
    private static func worstVerdict(of verdicts: [AuthenticationVerdict]) -> AuthenticationVerdict {
        let severityOrder: [AuthenticationVerdict] = [.fail, .warning, .unverified, .unknown, .pass]
        for candidate in severityOrder where verdicts.contains(candidate) {
            return candidate
        }
        return .unknown
    }
}
