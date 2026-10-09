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

    /// Whether to analyze each message with Apple's on-device Apple Intelligence model (a
    /// legitimacy score, a short prose analysis, and a follow-up chat), when it's available —
    /// macOS 27+ with Apple Intelligence enabled on eligible hardware. On by default: all of
    /// this runs entirely on-device, so unlike this app's one network-touching feature (brand
    /// images), there's no remote request to be cautious about, just a result that — like any
    /// model output — can be confidently wrong.
    var isAIInsightsEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isAIInsightsEnabled, forKey: Self.isAIInsightsEnabledKey)
        }
    }

    /// Whether the Apple Intelligence chat is allowed to attach a decoded excerpt of the
    /// message's own text content to a question, when the user explicitly asks it to. Off by
    /// default: the body is otherwise never decoded anywhere in this app, the excerpt is raw
    /// (not MIME-aware, so it can look like encoded gibberish for most real-world messages), and
    /// attacker-controlled text is a real prompt-injection surface even when processed on-device.
    var allowIncludingMessageTextInAIChat: Bool {
        didSet {
            UserDefaults.standard.set(allowIncludingMessageTextInAIChat, forKey: Self.allowIncludingMessageTextInAIChatKey)
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
    }
}
