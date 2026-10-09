//
//  Mail Inspector
//
//  Copyright (c) 2026 Nicholas K. Dionysopoulos
//  Licensed under the MIT License. See license.txt in the project root for details.
//

import Testing
import Foundation
@testable import Mail_Inspector

/// Tests for `PublicSuffixList`: computing the organizational domain one label below the
/// longest matching public suffix, with a sane fallback for unrecognized single-label input.
@Suite("PublicSuffixList")
struct PublicSuffixListTests {
    @Test("Computes the organizational domain one label below the longest matching suffix")
    func organizationalDomainUsesLongestMatch() {
        #expect(PublicSuffixList.shared.organizationalDomain(of: "mail.ministry.gov.gr") == "ministry.gov.gr")
        #expect(PublicSuffixList.shared.organizationalDomain(of: "example.com") == "example.com")
        #expect(PublicSuffixList.shared.organizationalDomain(of: "mail.example.com") == "example.com")
    }

    @Test("Falls back to the last label for an unrecognized single-label input")
    func singleLabelDomainReturnsItself() {
        #expect(PublicSuffixList.shared.organizationalDomain(of: "localhost") == "localhost")
    }
}
