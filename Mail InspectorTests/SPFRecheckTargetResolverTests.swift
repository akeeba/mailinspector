//
//  Mail Inspector
//
//  Copyright (c) 2026 Nicholas K. Dionysopoulos / Akeeba Ltd
//  Licensed under the MIT License. See license.txt in the project root for details.
//

import Testing
import Foundation
@testable import Mail_Inspector

/// Tests for `SPFRecheckTargetResolver`: choosing the IP/domain pair to use for a manual SPF
/// recheck — preferring a `Received-SPF` header when present, falling back to
/// `Authentication-Results` smtp.mailfrom/smtp.client-ip, and returning nil when neither source
/// has enough information.
@Suite("SPFRecheckTargetResolver")
struct SPFRecheckTargetResolverTests {
    @Test("Prefers a Received-SPF header when one is present with both fields")
    func prefersReceivedSPF() throws {
        let raw = "From: a@epafos.gr\r\n" +
            "Received-SPF: pass client-ip=51.145.238.12; envelope-from=4schools-info@epafos.gr;\r\n" +
            "Authentication-Results: mx.google.com; spf=pass smtp.mailfrom=other@other.example smtp.client-ip=9.9.9.9\r\n\r\n"
        let message = try makeTestMessage(raw)
        let authentication = AuthenticationAnalyzer.analyze(message: message, trustedAuthServIDs: [], trustAllByDefault: true)
        let target = SPFRecheckTargetResolver.resolve(message: message, authentication: authentication)
        #expect(target?.source == "Received-SPF")
        #expect(target?.ip == "51.145.238.12")
        #expect(target?.domain == "epafos.gr")
    }

    @Test("Falls back to Authentication-Results smtp.mailfrom/smtp.client-ip when there's no Received-SPF header")
    func fallsBackToAuthenticationResults() throws {
        let raw = "From: a@example.com\r\n" +
            "Authentication-Results: mx.google.com; spf=pass smtp.mailfrom=sender@example.com smtp.client-ip=9.9.9.9\r\n\r\n"
        let message = try makeTestMessage(raw)
        let authentication = AuthenticationAnalyzer.analyze(message: message, trustedAuthServIDs: [], trustAllByDefault: true)
        let target = SPFRecheckTargetResolver.resolve(message: message, authentication: authentication)
        #expect(target?.ip == "9.9.9.9")
        #expect(target?.domain == "example.com")
    }

    @Test("Returns nil when neither source has enough information")
    func returnsNilWithoutEnoughInformation() throws {
        let message = try makeTestMessage("From: a@example.com\r\n\r\n")
        let authentication = AuthenticationAnalyzer.analyze(message: message, trustedAuthServIDs: [], trustAllByDefault: true)
        #expect(SPFRecheckTargetResolver.resolve(message: message, authentication: authentication) == nil)
    }
}
