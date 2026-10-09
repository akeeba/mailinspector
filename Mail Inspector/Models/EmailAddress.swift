//
//  Mail Inspector
//
//  Copyright (c) 2026 Nicholas K. Dionysopoulos
//  Licensed under the MIT License. See license.txt in the project root for details.
//

import Foundation

/// A single parsed mailbox (display name + local-part@domain), per RFC 5322 `mailbox`.
nonisolated struct EmailAddress: Sendable, Equatable, Hashable, Identifiable {
    var displayName: String?
    var localPart: String
    var domain: String

    var id: String { address }

    var address: String {
        domain.isEmpty ? localPart : "\(localPart)@\(domain)"
    }
}

/// A single entry in an RFC 5322 address-list header (`From`, `To`, `Cc`, `Reply-To`, ...).
///
/// Group syntax (`Team: a@b.com, c@d.com;`) and unparseable segments are preserved rather than
/// silently dropped, since both can be used to obscure the true sender in a forged message.
nonisolated enum AddressListEntry: Sendable, Equatable {
    case mailbox(EmailAddress)
    case group(displayName: String, members: [EmailAddress])
    case malformed(raw: String)
}
