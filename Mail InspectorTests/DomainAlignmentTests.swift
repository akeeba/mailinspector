//
//  Mail Inspector
//
//  Copyright (c) 2026 Nicholas K. Dionysopoulos
//  Licensed under the MIT License. See license.txt in the project root for details.
//

import Testing
import Foundation
@testable import Mail_Inspector

/// Tests for `DomainAlignment`: DMARC-style strict/relaxed/not-aligned domain comparison,
/// including multi-label public suffixes (e.g. `co.uk`, `gov.gr`) where a naive two-label
/// guess would compute the wrong organizational domain.
@Suite("DomainAlignment")
struct DomainAlignmentTests {
    @Test("Identical domains are strictly aligned")
    func exactMatch() {
        #expect(DomainAlignment.align("example.com", "example.com") == .strict)
    }

    @Test("A subdomain is relaxed-aligned with its parent organizational domain")
    func subdomainIsRelaxedAligned() {
        #expect(DomainAlignment.align("mail.example.com", "example.com") == .relaxed)
    }

    @Test("Unrelated domains are not aligned")
    func unrelatedDomainsAreNotAligned() {
        #expect(DomainAlignment.align("example.com", "evil.example") == .notAligned)
    }

    @Test("Recognizes common multi-label suffixes when computing the organizational domain")
    func multiLabelSuffix() {
        #expect(DomainAlignment.align("mail.example.co.uk", "example.co.uk") == .relaxed)
        #expect(DomainAlignment.align("example.co.uk", "other.co.uk") == .notAligned)
    }

    @Test("Resolves gov.gr/gov.cy-style multi-label government suffixes using the public suffix list, not a two-label guess")
    func governmentMultiLabelSuffixes() {
        #expect(DomainAlignment.align("mail.ministry.gov.gr", "ministry.gov.gr") == .relaxed)
        #expect(DomainAlignment.align("ministry.gov.gr", "otherministry.gov.gr") == .notAligned)
        #expect(DomainAlignment.align("mail.example.gov.cy", "example.gov.cy") == .relaxed)
    }
}
