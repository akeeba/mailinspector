//
//  Mail Inspector
//
//  Copyright (c) 2026 Nicholas K. Dionysopoulos / Akeeba Ltd
//  Licensed under the MIT License. See license.txt in the project root for details.
//

import Testing
import Foundation
@testable import Mail_Inspector

/// Tests for `AuthenticationAnalyzer`: the SPF/DKIM/DMARC trust model itself — verdicts are
/// only derived from `Authentication-Results` headers whose authserv-id is trusted (explicitly
/// configured, or via `trustAllByDefault`), untrusted/forged headers never produce a trusted
/// Pass, and DMARC can fail even when SPF and DKIM individually pass but don't align.
@Suite("AuthenticationAnalyzer")
struct AuthenticationAnalyzerTests {
    @Test("A trusted server reporting SPF, DKIM, and DMARC pass yields Pass verdicts and strict alignment")
    func trustedPassEverything() throws {
        let raw = "From: billing@example.com\r\n" +
            "Authentication-Results: mx.ourcompany.com; spf=pass smtp.mailfrom=billing@example.com; dkim=pass header.d=example.com; dmarc=pass header.from=example.com\r\n\r\n"
        let message = try makeTestMessage(raw)
        let analysis = AuthenticationAnalyzer.analyze(message: message, trustedAuthServIDs: ["mx.ourcompany.com"])
        #expect(analysis.spf.verdict == .pass)
        #expect(analysis.dkim.verdict == .pass)
        #expect(analysis.dmarc.verdict == .pass)
        #expect(analysis.alignment.spfAlignment == .strict)
        #expect(analysis.alignment.dkimAlignment == .strict)
    }

    @Test("DMARC can fail despite SPF and DKIM individually passing, when neither aligns with the From domain")
    func dmarcFailsDespiteIndividualPasses() throws {
        let raw = "From: billing@example.com\r\n" +
            "Authentication-Results: mx.ourcompany.com;" +
            " spf=pass smtp.mailfrom=bounce@bounce.example.net;" +
            " dkim=pass header.d=mail-vendor.example.net;" +
            " dmarc=fail header.from=example.com\r\n\r\n"
        let message = try makeTestMessage(raw)
        let analysis = AuthenticationAnalyzer.analyze(message: message, trustedAuthServIDs: ["mx.ourcompany.com"])
        #expect(analysis.spf.verdict == .pass)
        #expect(analysis.dkim.verdict == .pass)
        #expect(analysis.dmarc.verdict == .fail)
        #expect(analysis.alignment.spfAlignment == .notAligned)
        #expect(analysis.alignment.dkimAlignment == .notAligned)
    }

    @Test("A forged Authentication-Results header from an untrusted server never produces a trusted Pass")
    func forgedHeaderFromUntrustedServerIsNotTrusted() throws {
        let raw = "From: victim@example.com\r\n" +
            "Authentication-Results: attacker-mx.evil.example; spf=pass dkim=pass dmarc=pass\r\n\r\n"
        let message = try makeTestMessage(raw)
        // No trusted servers configured at all.
        let analysis = AuthenticationAnalyzer.analyze(message: message, trustedAuthServIDs: ["mx.ourcompany.com"])
        #expect(analysis.spf.verdict == .unknown)
        #expect(analysis.dkim.verdict == .unknown)
        #expect(analysis.dmarc.verdict == .unknown)
        #expect(analysis.spf.trustedResults.isEmpty)
        #expect(analysis.spf.unverifiedResults.count == 1)
        #expect(analysis.spf.unverifiedResults[0].authServID == "attacker-mx.evil.example")
    }

    @Test("Multiple Authentication-Results headers from different servers: only the trusted one drives the verdict")
    func onlyTrustedServerDrivesVerdict() throws {
        let raw = "From: a@example.com\r\n" +
            "Authentication-Results: mx.ourcompany.com; spf=fail smtp.mailfrom=a@evil.example\r\n" +
            "Authentication-Results: relay.someisp.net; spf=pass smtp.mailfrom=a@evil.example\r\n\r\n"
        let message = try makeTestMessage(raw)
        let analysis = AuthenticationAnalyzer.analyze(message: message, trustedAuthServIDs: ["mx.ourcompany.com"])
        #expect(analysis.spf.verdict == .fail)
        #expect(analysis.spf.trustedResults.count == 1)
        #expect(analysis.spf.unverifiedResults.count == 1)
    }

    @Test("trustAllByDefault treats every authserv-id as trusted without an explicit allowlist")
    func trustAllByDefaultBypassesTheAllowlist() throws {
        let raw = "From: a@example.com\r\n" +
            "Authentication-Results: mx.google.com; spf=pass smtp.mailfrom=a@example.com; dkim=pass header.d=example.com\r\n\r\n"
        let message = try makeTestMessage(raw)
        let analysis = AuthenticationAnalyzer.analyze(message: message, trustedAuthServIDs: [], trustAllByDefault: true)
        #expect(analysis.spf.verdict == .pass)
        #expect(analysis.spf.trustedResults.count == 1)
        #expect(analysis.spf.unverifiedResults.isEmpty)
    }

    @Test("A message with no Authentication-Results headers reports Unknown for every method")
    func missingAuthenticationInfoIsUnknown() throws {
        let message = try makeTestMessage("From: a@example.com\r\n\r\n")
        let analysis = AuthenticationAnalyzer.analyze(message: message, trustedAuthServIDs: ["mx.ourcompany.com"])
        #expect(analysis.spf.verdict == .unknown)
        #expect(analysis.dkim.verdict == .unknown)
        #expect(analysis.dmarc.verdict == .unknown)
        #expect(analysis.authenticationResultsHeaders.isEmpty)
    }
}
