//
//  Mail Inspector
//
//  Copyright (c) 2026 Nicholas K. Dionysopoulos
//  Licensed under the MIT License. See license.txt in the project root for details.
//

import Foundation

nonisolated struct AdditionalSecurityHeader: Sendable, Identifiable {
    let id: Int
    let name: String
    let value: String
    let explanation: String
}

/// Known mail-filtering and chain-of-custody headers this app doesn't otherwise parse
/// structurally, shown with a plain-language explanation of what each represents.
///
/// This deliberately does not attempt to implement any proprietary spam-scoring system — it
/// only surfaces the raw value a filter already computed, with context for what that value
/// means. Headers not in this catalog but still present on the message are available in the
/// raw headers view; nothing is hidden, this just adds explanations for the common ones.
nonisolated enum SecurityHeaderCatalog {
    private static let knownHeaders: [(name: String, explanation: String)] = [
        ("Received-SPF", "A legacy way some servers recorded an SPF result directly on its own header, before Authentication-Results (RFC 8601) standardized reporting SPF/DKIM/DMARC results together."),
        ("ARC-Authentication-Results", "Part of ARC (Authenticated Received Chain, RFC 8617): the authentication results an intermediary saw before forwarding this message. ARC lets SPF/DKIM survive being forwarded through a mailing list or similar relay that would otherwise break them."),
        ("ARC-Message-Signature", "Part of ARC: a DKIM-style signature over the message as the ARC-sealing intermediary saw it."),
        ("ARC-Seal", "Part of ARC: a signature over the ARC header set itself, chaining each intermediary's seal to the one before it."),
        ("X-Spam-Status", "A spam filter's verdict and scoring details. The exact format and scoring method are specific to whichever filter produced it (commonly SpamAssassin)."),
        ("X-Spam-Score", "A numeric spam score from a spam filter. A higher number usually means more likely to be spam, but the scale and threshold are filter-specific."),
        ("X-Spam-Flag", "A simple yes/no spam-filter verdict."),
        ("X-Microsoft-Antispam", "Microsoft 365 / Exchange Online Protection's anti-spam metadata: bulk-mail classification, phishing confidence level, and similar internal scoring."),
        ("X-Microsoft-Antispam-Message-Info", "Additional Microsoft 365 anti-spam routing metadata."),
        ("X-Forefront-Antispam-Report", "Microsoft Forefront / Exchange Online Protection's detailed anti-spam report."),
        ("X-MS-Exchange-Organization-SCL", "Exchange's Spam Confidence Level: a number (typically -1 to 9) indicating how likely Exchange judged this message to be spam."),
        ("X-Google-Smtp-Source", "Gmail / Google Workspace's internal relay metadata."),
        ("X-Originating-IP", "An IP address some mail systems record for the message's original sender, separately from the Received chain."),
        ("X-Rspamd-Score", "The score Rspamd (an open-source spam filter used by mailbox.org and others) assigned this message, typically shown as \"score / required-score / reject-score\". Higher means more likely to be spam."),
        ("X-Rspamd-Queue-Id", "Rspamd's internal queue identifier for this message — useful for looking it up in the filter's own logs, not a security signal on its own."),
        ("X-MBO-SPAM-Probability", "mailbox.org's own spam-probability estimate, separate from the Rspamd score it also reports.")
    ]

    static func presentHeaders(in parsed: ParsedEmail) -> [AdditionalSecurityHeader] {
        var results: [AdditionalSecurityHeader] = []
        var nextID = 0
        for entry in knownHeaders {
            for header in parsed.headers(named: entry.name) {
                results.append(AdditionalSecurityHeader(id: nextID, name: header.name, value: header.unfoldedValue, explanation: entry.explanation))
                nextID += 1
            }
        }
        return results
    }
}
