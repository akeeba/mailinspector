//
//  Mail Inspector
//
//  Copyright (c) 2026 Nicholas K. Dionysopoulos / Akeeba Ltd
//  Licensed under the MIT License. See license.txt in the project root for details.
//

import Testing
import Foundation
@testable import Mail_Inspector

/// Tests for `AddressParser`: parsing RFC 5322 address lists — mailboxes, groups, comments,
/// quoted display names, RFC 2047 encoded words, and malformed/unparseable segments.
@Suite("AddressParser")
struct AddressParserTests {
    @Test("Parses a simple angle-addr mailbox with display name")
    func displayNameAndAngleAddr() {
        let entries = AddressParser.parseAddressList("Alice Example <alice@example.com>")
        guard case .mailbox(let address) = entries.first else {
            Issue.record("Expected a mailbox entry")
            return
        }
        #expect(address.displayName == "Alice Example")
        #expect(address.address == "alice@example.com")
    }

    @Test("Parses a bare addr-spec with no display name")
    func bareAddrSpec() {
        let entries = AddressParser.parseAddressList("alice@example.com")
        guard case .mailbox(let address) = entries.first else {
            Issue.record("Expected a mailbox entry")
            return
        }
        #expect(address.displayName == nil)
        #expect(address.address == "alice@example.com")
    }

    @Test("Parses a quoted display name that itself contains an email address, surfacing the mismatch")
    func quotedDisplayNameContainingAddress() {
        let entries = AddressParser.parseAddressList("\"support@bank.com\" <attacker@evil.example>")
        guard case .mailbox(let address) = entries.first else {
            Issue.record("Expected a mailbox entry")
            return
        }
        #expect(address.displayName == "support@bank.com")
        #expect(address.address == "attacker@evil.example")
    }

    @Test("Parses a comma-separated address list")
    func multipleAddresses() {
        let entries = AddressParser.parseAddressList("a@b.com, Bob <bob@c.com>, \"Carol C\" <carol@d.com>")
        #expect(entries.count == 3)
    }

    @Test("Skips comments embedded in an address")
    func addressWithComment() {
        let entries = AddressParser.parseAddressList("alice@example.com (this is a comment)")
        guard case .mailbox(let address) = entries.first else {
            Issue.record("Expected a mailbox entry")
            return
        }
        #expect(address.address == "alice@example.com")
    }

    @Test("Parses group syntax and flattens its members")
    func groupSyntax() {
        let entries = AddressParser.parseAddressList("Undisclosed: a@b.com, c@d.com;")
        guard case .group(let name, let members) = entries.first else {
            Issue.record("Expected a group entry")
            return
        }
        #expect(name == "Undisclosed")
        #expect(members.map(\.address) == ["a@b.com", "c@d.com"])
    }

    @Test("Preserves an unparseable segment as malformed instead of silently dropping it")
    func malformedSegmentPreserved() {
        let entries = AddressParser.parseAddressList("not an address, bob@example.com")
        #expect(entries.contains { if case .malformed = $0 { return true } else { return false } })
        #expect(entries.contains { if case .mailbox(let a) = $0 { return a.address == "bob@example.com" } else { return false } })
    }

    @Test("Decodes an RFC 2047 encoded display name")
    func encodedWordDisplayName() {
        let entries = AddressParser.parseAddressList("=?UTF-8?B?zp3Or866zr/Pgg==?= <test@example.com>")
        guard case .mailbox(let address) = entries.first else {
            Issue.record("Expected a mailbox entry")
            return
        }
        #expect(address.displayName == "Νίκος")
    }

    @Test("Parses an IDN/Punycode domain as an ordinary domain token")
    func punycodeDomain() {
        let entries = AddressParser.parseAddressList("user@xn--mnich-kva.example")
        guard case .mailbox(let address) = entries.first else {
            Issue.record("Expected a mailbox entry")
            return
        }
        #expect(address.domain == "xn--mnich-kva.example")
    }
}
