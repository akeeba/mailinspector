//
//  Mail Inspector
//
//  Copyright (c) 2026 Nicholas K. Dionysopoulos
//  Licensed under the MIT License. See license.txt in the project root for details.
//

import Foundation
import Observation

/// User-configurable settings for the inspector. Holds no message content.
@Observable
@MainActor
final class InspectorSettings {
    static let defaultMaxMessageSizeBytes = 25 * 1024 * 1024
    private static let trustedAuthServIDsKey = "trustedAuthServIDs"
    private static let publicSuffixListUpdateEnabledKey = "publicSuffixListUpdateEnabled"
    private static let trustAllAuthenticationResultsByDefaultKey = "trustAllAuthenticationResultsByDefault"
    private static let trustServerSpamHeadersKey = "trustServerSpamHeaders"
    private static let isObservationsSummaryEnabledKey = "isObservationsSummaryEnabled"
    private static let reportPageSizeKey = "reportPageSize"
    private static let showBrandImagesKey = "showBrandImages"
    private static let hideBrandImagesForMessagesWithoutSpamScoreKey = "hideBrandImagesForMessagesWithoutSpamScore"
    private static let hideBrandImagesAboveSpamThresholdKey = "hideBrandImagesAboveSpamThreshold"
    private static let isAIInsightsEnabledKey = "isAIInsightsEnabled"
    private static let allowIncludingMessageTextInAIChatKey = "allowIncludingMessageTextInAIChat"
    private static let aiActiveProviderKeyKey = "aiActiveProviderKey"
    private static let aiProviderEndpointsKey = "aiProviderEndpoints"
    private static let aiProviderModelNamesKey = "aiProviderModelNames"
    private static let trustedReplyToDomainsByRecipientKey = "trustedReplyToDomainsByRecipient"
    private static let trustedHostnameMismatchesKey = "trustedHostnameMismatches"

    var maxMessageSizeBytes: Int = InspectorSettings.defaultMaxMessageSizeBytes

    /// `authserv-id` values (from `Authentication-Results` headers) the user has told the app to
    /// treat as trusted. Only consulted when `trustAllAuthenticationResultsByDefault` is off —
    /// see that property's documentation for why there are two settings here, not one.
    var trustedAuthServIDs: [String] {
        didSet {
            UserDefaults.standard.set(trustedAuthServIDs, forKey: Self.trustedAuthServIDsKey)
        }
    }

    /// When on (the default), every `Authentication-Results` header is treated as a trusted
    /// report regardless of its `authserv-id`, instead of requiring each one to be explicitly
    /// added to `trustedAuthServIDs`. This trades the stricter, spec-literal "trust nothing
    /// until told otherwise" posture for one that matches how most people actually use this:
    /// the receiving server that handed you the message is, in practice, the one you're relying
    /// on already. Turn this off for the stricter allowlist-only behavior.
    var trustAllAuthenticationResultsByDefault: Bool {
        didSet {
            UserDefaults.standard.set(trustAllAuthenticationResultsByDefault, forKey: Self.trustAllAuthenticationResultsByDefaultKey)
        }
    }

    /// Whether `PublicSuffixList` is allowed to download a fresh copy of the list (at most once
    /// a week) for accurate organizational-domain comparisons. Disabling this (and never using
    /// the manually-triggered SPF recheck) keeps the app fully offline, falling back to a small
    /// bundled list that covers common cases less precisely.
    var isPublicSuffixListUpdateEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isPublicSuffixListUpdateEnabled, forKey: Self.publicSuffixListUpdateEnabledKey)
        }
    }

    /// Whether to treat spam-filter headers (X-Spam-Score, X-Microsoft-Antispam's SCL, etc.) as
    /// trustworthy enough to derive a spam-likelihood gauge from. Off by default: unlike
    /// SPF/DKIM/DMARC, these headers follow no standard, their scoring is entirely
    /// filter-specific, and a gauge built from them is an approximation of what a *filter*
    /// reported, not anything this app independently determined.
    var trustServerSpamHeaders: Bool {
        didSet {
            UserDefaults.standard.set(trustServerSpamHeaders, forKey: Self.trustServerSpamHeadersKey)
        }
    }

    /// Whether to show the "Noteworthy Observations" summary (sender-identity discrepancies and
    /// delivery-path anomalies) at the top of a message. Off by default: in practice, most of
    /// what it flags is delivery hops within a legitimate sender's own SaaS infrastructure
    /// (an app server relaying through an internal mail sender, for instance), which is normal
    /// and not actually noteworthy — not a message-specific red flag.
    var isObservationsSummaryEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isObservationsSummaryEnabled, forKey: Self.isObservationsSummaryEnabledKey)
        }
    }

    /// The page size used when exporting or sharing the report as a PDF.
    var reportPageSize: ReportPageSize {
        didSet {
            UserDefaults.standard.set(reportPageSize.rawValue, forKey: Self.reportPageSizeKey)
        }
    }

    /// Whether to look up and display a sender's BIMI (Brand Indicators for Message
    /// Identification) logo next to their identity, when DMARC is a trusted pass. Off by
    /// default: this is the one feature in the app that renders an image fetched from a
    /// remote, sender-controlled URL — a malicious or compromised logo host could use it as an
    /// attack vector against an unpatched vulnerability in macOS's image-decoding pipeline, the
    /// same risk class as opening an image attachment from an untrusted sender. Decoding uses
    /// the system's own `NSImage`, not some separate, sandboxed decoder, so that risk is real,
    /// not theoretical.
    var showBrandImages: Bool {
        didSet {
            UserDefaults.standard.set(showBrandImages, forKey: Self.showBrandImagesKey)
        }
    }

    /// When `showBrandImages` is on: whether to suppress the brand image for a message with no
    /// available spam score at all (either because `trustServerSpamHeaders` is off, or because
    /// this particular message has no recognized spam-scoring header). On by default — no score
    /// to compare against a threshold is itself a reason for caution before fetching a remote
    /// image tied to an unscored message.
    var hideBrandImagesForMessagesWithoutSpamScore: Bool {
        didSet {
            UserDefaults.standard.set(hideBrandImagesForMessagesWithoutSpamScore, forKey: Self.hideBrandImagesForMessagesWithoutSpamScoreKey)
        }
    }

    /// When `showBrandImages` is on: suppresses the brand image once a message's spam-likelihood
    /// percentage exceeds this threshold (0–100). Only consulted when a spam score is actually
    /// available — see `hideBrandImagesForMessagesWithoutSpamScore` for the no-score case.
    var hideBrandImagesAboveSpamThreshold: Double {
        didSet {
            UserDefaults.standard.set(hideBrandImagesAboveSpamThreshold, forKey: Self.hideBrandImagesAboveSpamThresholdKey)
        }
    }

    /// Whether to analyze each message with AI (a legitimacy score, a short prose analysis, and
    /// a follow-up chat), using whichever backend `aiActiveProviderKey` selects. On by default:
    /// the default backend (On-Device Apple Intelligence) runs entirely on-device, so there's no
    /// remote request to be cautious about there — just a result that, like any model output,
    /// can be confidently wrong. Switching to a remote provider is a separate, explicit choice
    /// (see `aiActiveProviderKey`), each with its own privacy disclosure in Settings.
    var isAIInsightsEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isAIInsightsEnabled, forKey: Self.isAIInsightsEnabledKey)
        }
    }

    /// Whether the AI chat is allowed to attach a decoded excerpt of the message's own text
    /// content to a question, when the user explicitly asks it to. Off by default: the body is
    /// otherwise never decoded anywhere in this app, the excerpt is raw (not MIME-aware, so it
    /// can look like encoded gibberish for most real-world messages), and attacker-controlled
    /// text is a real prompt-injection surface — doubly so once it may be sent to a remote
    /// provider rather than staying on-device.
    var allowIncludingMessageTextInAIChat: Bool {
        didSet {
            UserDefaults.standard.set(allowIncludingMessageTextInAIChat, forKey: Self.allowIncludingMessageTextInAIChatKey)
        }
    }

    /// Which entry in `AIProviderCatalog` is active. Defaults to On-Device Apple Intelligence —
    /// zero-config and already works for anyone who has it enabled. LM Studio is listed first in
    /// the picker and marked "Recommended" (local, private, and far better at non-English text),
    /// but switching to it — or to any other provider — is always an explicit choice, never
    /// automatic. API keys are never stored here — see `AIKeychainStore`.
    var aiActiveProviderKey: String {
        didSet {
            UserDefaults.standard.set(aiActiveProviderKey, forKey: Self.aiActiveProviderKeyKey)
        }
    }

    /// Remembers each provider's endpoint URL across switches, so going back to a previously
    /// configured provider doesn't require retyping it. Not a secret — just a server address.
    var aiProviderEndpoints: [String: String] {
        didSet {
            UserDefaults.standard.set(aiProviderEndpoints, forKey: Self.aiProviderEndpointsKey)
        }
    }

    /// Remembers each provider's chosen model name across switches. Not a secret.
    var aiProviderModelNames: [String: String] {
        didSet {
            UserDefaults.standard.set(aiProviderModelNames, forKey: Self.aiProviderModelNamesKey)
        }
    }

    /// Reply-To domains explicitly marked safe for specific recipients of the user's own — e.g.
    /// a sales alias whose replies are deliberately routed to a different domain's help desk.
    /// Keyed by lowercased recipient address; each value is the list of lowercased Reply-To
    /// domains trusted for that recipient. Grown only via `trustReplyToDomain(_:forRecipients:)`,
    /// driven by a "Mark as Safe" action next to the mismatch itself in the report — not meant to
    /// be hand-typed.
    var trustedReplyToDomainsByRecipient: [String: [String]] {
        didSet {
            UserDefaults.standard.set(trustedReplyToDomainsByRecipient, forKey: Self.trustedReplyToDomainsByRecipientKey)
        }
    }

    /// Claimed/verified hostname pairs explicitly marked safe — e.g. an internal proxy whose
    /// external-facing hostname legitimately differs from its reverse-DNS name. Grown only via
    /// `trustHostnameMismatch(claimed:verified:)`.
    var trustedHostnameMismatches: [TrustedHostnameMismatch] {
        didSet {
            if let data = try? JSONEncoder().encode(trustedHostnameMismatches) {
                UserDefaults.standard.set(data, forKey: Self.trustedHostnameMismatchesKey)
            }
        }
    }

    init() {
        trustedAuthServIDs = UserDefaults.standard.stringArray(forKey: Self.trustedAuthServIDsKey) ?? []
        trustAllAuthenticationResultsByDefault = UserDefaults.standard.object(forKey: Self.trustAllAuthenticationResultsByDefaultKey) as? Bool ?? true
        isPublicSuffixListUpdateEnabled = UserDefaults.standard.object(forKey: Self.publicSuffixListUpdateEnabledKey) as? Bool ?? true
        trustServerSpamHeaders = UserDefaults.standard.object(forKey: Self.trustServerSpamHeadersKey) as? Bool ?? false
        isObservationsSummaryEnabled = UserDefaults.standard.object(forKey: Self.isObservationsSummaryEnabledKey) as? Bool ?? false
        reportPageSize = UserDefaults.standard.string(forKey: Self.reportPageSizeKey)
            .flatMap(ReportPageSize.init(rawValue:)) ?? .usLetter
        showBrandImages = UserDefaults.standard.object(forKey: Self.showBrandImagesKey) as? Bool ?? false
        hideBrandImagesForMessagesWithoutSpamScore = UserDefaults.standard.object(forKey: Self.hideBrandImagesForMessagesWithoutSpamScoreKey) as? Bool ?? true
        hideBrandImagesAboveSpamThreshold = UserDefaults.standard.object(forKey: Self.hideBrandImagesAboveSpamThresholdKey) as? Double ?? 25
        isAIInsightsEnabled = UserDefaults.standard.object(forKey: Self.isAIInsightsEnabledKey) as? Bool ?? true
        allowIncludingMessageTextInAIChat = UserDefaults.standard.object(forKey: Self.allowIncludingMessageTextInAIChatKey) as? Bool ?? false
        aiActiveProviderKey = UserDefaults.standard.string(forKey: Self.aiActiveProviderKeyKey) ?? AIProviderCatalog.onDevice.key
        aiProviderEndpoints = UserDefaults.standard.dictionary(forKey: Self.aiProviderEndpointsKey) as? [String: String] ?? [:]
        aiProviderModelNames = UserDefaults.standard.dictionary(forKey: Self.aiProviderModelNamesKey) as? [String: String] ?? [:]
        trustedReplyToDomainsByRecipient = UserDefaults.standard.dictionary(forKey: Self.trustedReplyToDomainsByRecipientKey) as? [String: [String]] ?? [:]
        if let data = UserDefaults.standard.data(forKey: Self.trustedHostnameMismatchesKey),
           let decoded = try? JSONDecoder().decode([TrustedHostnameMismatch].self, from: data) {
            trustedHostnameMismatches = decoded
        } else {
            trustedHostnameMismatches = []
        }
    }

    /// Marks a Reply-To domain safe for every given recipient — called from the "Mark as Safe"
    /// action next to a Reply-To mismatch in the report, never meant to be hand-typed.
    func trustReplyToDomain(_ domain: String, forRecipients recipients: [String]) {
        let normalizedDomain = domain.lowercased()
        for recipient in recipients {
            let key = recipient.lowercased()
            var domains = trustedReplyToDomainsByRecipient[key] ?? []
            guard !domains.contains(normalizedDomain) else { continue }
            domains.append(normalizedDomain)
            trustedReplyToDomainsByRecipient[key] = domains
        }
    }

    /// Removes a single recipient/Reply-To-domain trust entry — used by Settings' review list.
    func removeTrustedReplyToDomain(_ domain: String, forRecipient recipient: String) {
        let key = recipient.lowercased()
        guard var domains = trustedReplyToDomainsByRecipient[key] else { return }
        domains.removeAll { $0.caseInsensitiveCompare(domain) == .orderedSame }
        if domains.isEmpty {
            trustedReplyToDomainsByRecipient.removeValue(forKey: key)
        } else {
            trustedReplyToDomainsByRecipient[key] = domains
        }
    }

    /// Marks a claimed/verified hostname pair safe — called from the "Mark as Safe" action next
    /// to a delivery-hop hostname-mismatch warning, never meant to be hand-typed.
    func trustHostnameMismatch(claimed: String, verified: String) {
        let entry = TrustedHostnameMismatch(claimed: claimed, verified: verified)
        guard !trustedHostnameMismatches.contains(entry) else { return }
        trustedHostnameMismatches.append(entry)
    }

    /// Removes a single trusted hostname pair — used by Settings' review list.
    func removeTrustedHostnameMismatch(_ entry: TrustedHostnameMismatch) {
        trustedHostnameMismatches.removeAll { $0 == entry }
    }
}
