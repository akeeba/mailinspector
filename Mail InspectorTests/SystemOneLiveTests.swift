//
//  Mail Inspector
//
//  Copyright (c) 2026 Nicholas K. Dionysopoulos / Akeeba Ltd
//  Licensed under the MIT License. See license.txt in the project root for details.
//

import Testing
import Foundation
@testable import Mail_Inspector

/// Live tests against the real Jev / System One-compatible service. Deliberately reads no secret
/// of its own: credentials and configuration come from whatever's already been saved through the
/// running app's own Settings UI — the Keychain item `AIKeychainStore` writes, and the
/// `UserDefaults` entries `InspectorSettings` persists — exactly as `SystemOneAIEngine` itself
/// would read them via `AIEngineFactory`. This test bundle runs hosted inside the app process
/// (`TEST_HOST`), so it shares that Keychain item and `UserDefaults` domain directly; nothing is
/// hardcoded here. Skipped entirely wherever no Jev API key has been configured — see
/// `.claude/docs/system-one-jev.md` for how to set this up locally.
@Suite("SystemOneAIEngine (live)")
struct SystemOneLiveTests {
    // Explicitly `nonisolated`: the `.enabled(if:)` trait below evaluates its autoclosure during
    // test discovery, off the main actor — these need to be callable from there, unlike the
    // `@MainActor`-isolated test functions themselves (required by `SystemOneAIEngine`).
    nonisolated private static var jevApiKey: String? { AIKeychainStore.get(forProvider: AIProviderCatalog.jev.key) }

    nonisolated private static var compatibleEndpoint: String? {
        let endpoint = UserDefaults.standard.dictionary(forKey: "aiProviderEndpoints")?["systemone_compatible"] as? String
        return (endpoint?.isEmpty == false) ? endpoint : nil
    }

    @Test("Jev scores an obviously legitimate signal digest higher than an obviously forged one", .enabled(if: jevApiKey != nil))
    @MainActor
    func jevDiscriminatesLegitimateFromForged() async throws {
        let engine = SystemOneAIEngine(
            definition: AIProviderCatalog.jev,
            endpoint: AIProviderCatalog.jev.defaultEndpoint,
            apiKey: try #require(Self.jevApiKey),
            prompt: SystemOneAIEngine.defaultPrompt,
            contextLength: nil
        )

        let legitimate = try await engine.generateScore(signalsSummary: Self.legitimateDigest)
        let forged = try await engine.generateScore(signalsSummary: Self.forgedDigest)

        #expect(legitimate.score > forged.score)
        // The legitimate digest below deliberately includes a [notable]-tagged hop and
        // sender-identity line — routine noise that must NOT drag the score down alongside clean
        // SPF/DKIM/DMARC. See `SystemOneAIEngine.defaultPrompt`'s doc comment for why this
        // distinction exists at all (live testing on 2026-10-09 found Jev pessimistic without it).
        #expect(legitimate.score >= 60)
        #expect(forged.score <= 40)
    }

    @Test("A configured System One compatible endpoint also discriminates legitimate from forged", .enabled(if: compatibleEndpoint != nil))
    @MainActor
    func systemOneCompatibleDiscriminatesLegitimateFromForged() async throws {
        let definition = AIProviderCatalog.systemOneCompatible
        let apiKey = AIKeychainStore.get(forProvider: definition.key)
        let contextLength = (UserDefaults.standard.dictionary(forKey: "aiProviderContextLengths")?[definition.key] as? Int) ?? 8192
        let engine = SystemOneAIEngine(
            definition: definition,
            endpoint: try #require(Self.compatibleEndpoint),
            apiKey: apiKey,
            prompt: SystemOneAIEngine.defaultPrompt,
            contextLength: contextLength
        )

        let legitimate = try await engine.generateScore(signalsSummary: Self.legitimateDigest)
        let forged = try await engine.generateScore(signalsSummary: Self.forgedDigest)

        #expect(legitimate.score > forged.score)
        #expect(legitimate.score >= 60)
        #expect(forged.score <= 40)
    }

    // Shaped exactly like `EmailSignalsSummary.build`'s real output (including its
    // `[notable]`/`[warning]` severity tags on delivery-path and sender-identity lines) rather
    // than paraphrased English, so these fixtures actually exercise the same digest format the
    // app sends in production — paraphrased fixtures wouldn't have caught the pessimism bug this
    // prompt was recalibrated for.
    private static let legitimateDigest = """
        Subject: Your October invoice is ready
        From: Example SaaS <billing@example.com>
        Return-Path: billing@example.com
        SPF: pass
        DKIM: pass
        DMARC: pass
        DMARC alignment for From domain example.com:
        - SPF-checked domain example.com: aligned (identical domain)
        - DKIM-signing domain example.com: aligned (identical domain)
        Delivery hops: 3
        - Hop (mta-relay.example.com) [notable]: Unresolvable reverse-DNS hostname — routine for internal SaaS infrastructure
        - Sender-identity observation [notable]: Reply-To domain differs from From domain — billing@example.com vs support@example-billing.com, a common split for SaaS providers
        Spam filter score: 2% (Low, reported by X-Spam-Score: 2.0)
        """

    private static let forgedDigest = """
        Subject: Your account has been suspended — verify now
        From: Example Bank Security <security@example-bank-support.net>
        Return-Path: bounce@totally-unrelated.example
        SPF: fail
        DKIM: fail
        DMARC: fail
        DMARC alignment for From domain example-bank-support.net:
        - SPF-checked domain totally-unrelated.example: not aligned
        Delivery hops: 1
        - Hop (203.0.113.9) [warning]: Claimed hostname contradicts reverse DNS, a forged-looking mismatch
        - Sender-identity observation [warning]: Reply-To points to a free webmail address, unrelated to the claimed sender's domain
        Spam filter score: 96% (Very High, reported by X-Spam-Score: 9.6)
        """
}
