//
//  Mail Inspector
//
//  Copyright (c) 2026 Nicholas K. Dionysopoulos / Akeeba Ltd
//  Licensed under the MIT License. See license.txt in the project root for details.
//

import Foundation

/// A claimed-vs-verified hostname pair the user has explicitly marked safe — e.g. an internal
/// load balancer whose external-facing proxy hostname legitimately differs from its reverse-DNS
/// name (a real-world example: `4-vm-proxy01.<random>.ax.internal.cloudapp.net` claimed, but
/// `4-vm-proxy01.internal.cloudapp.net` found via reverse DNS). Normalizes both to lowercase at
/// construction so equality (and lookup in `DeliveryPathAnalyzer`) is always case-insensitive
/// without either side having to remember to call `.lowercased()` itself.
nonisolated struct TrustedHostnameMismatch: Codable, Sendable, Equatable, Hashable {
    let claimed: String
    let verified: String

    init(claimed: String, verified: String) {
        self.claimed = claimed.lowercased()
        self.verified = verified.lowercased()
    }
}
