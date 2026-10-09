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

    init() {
        trustedAuthServIDs = UserDefaults.standard.stringArray(forKey: Self.trustedAuthServIDsKey) ?? []
        trustAllAuthenticationResultsByDefault = UserDefaults.standard.object(forKey: Self.trustAllAuthenticationResultsByDefaultKey) as? Bool ?? true
        isPublicSuffixListUpdateEnabled = UserDefaults.standard.object(forKey: Self.publicSuffixListUpdateEnabledKey) as? Bool ?? true
        trustServerSpamHeaders = UserDefaults.standard.object(forKey: Self.trustServerSpamHeadersKey) as? Bool ?? false
        isObservationsSummaryEnabled = UserDefaults.standard.object(forKey: Self.isObservationsSummaryEnabledKey) as? Bool ?? false
        reportPageSize = UserDefaults.standard.string(forKey: Self.reportPageSizeKey)
            .flatMap(ReportPageSize.init(rawValue:)) ?? .usLetter
    }
}
