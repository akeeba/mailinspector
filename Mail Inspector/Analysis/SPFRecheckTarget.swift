//
//  Mail Inspector
//
//  Copyright (c) 2026 Nicholas K. Dionysopoulos
//  Licensed under the MIT License. See license.txt in the project root for details.
//

import Foundation

/// The (IP, domain) pair to re-run an SPF check against, and where that pair came from.
nonisolated struct SPFRecheckTarget: Sendable {
    let ip: String
    let domain: String
    let source: String
}

/// Finds the best available (IP, domain) pair to re-run an SPF check against, preferring the
/// most direct source: a `Received-SPF` header records exactly what was checked, so it's used
/// first; `Authentication-Results`' `smtp.mailfrom`/`smtp.client-ip` propspecs are the fallback
/// when no `Received-SPF` header exists or it's missing the needed fields.
nonisolated enum SPFRecheckTargetResolver {
    static func resolve(message: EmailMessage, authentication: AuthenticationAnalysis) -> SPFRecheckTarget? {
        if let header = message.parsed.firstHeader(named: "Received-SPF") {
            let parsed = ReceivedSPFParser.parse(header.unfoldedValue)
            if let ip = parsed.clientIP, let domain = parsed.envelopeFromDomain {
                return SPFRecheckTarget(ip: ip, domain: domain, source: "Received-SPF")
            }
        }

        for attributed in authentication.spf.attributedResults {
            let mailfromDomain = attributed.result.property(ptype: "smtp", "mailfrom").flatMap(Self.domain(fromAddress:))
            let ip = attributed.result.property(ptype: "smtp", "client-ip") ?? attributed.result.property(ptype: "smtp", "remote-ip")
            if let mailfromDomain, let ip {
                return SPFRecheckTarget(ip: ip, domain: mailfromDomain, source: "Authentication-Results (\(attributed.authServID))")
            }
        }

        return nil
    }

    private static func domain(fromAddress address: String) -> String? {
        guard let at = address.lastIndex(of: "@") else { return nil }
        let domain = String(address[address.index(after: at)...])
        return domain.isEmpty ? nil : domain
    }
}
