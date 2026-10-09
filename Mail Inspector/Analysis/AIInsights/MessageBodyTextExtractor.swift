//
//  Mail Inspector
//
//  Copyright (c) 2026 Nicholas K. Dionysopoulos / Akeeba Ltd
//  Licensed under the MIT License. See license.txt in the project root for details.
//

import Foundation

/// Produces a short, decoded excerpt of a message's body, for the one AI-chat feature that lets
/// the user explicitly attach it to a question (never used for the automatic score or prefab
/// analysis — see `EmailSignalsSummary`).
///
/// This is a best-effort raw decode, not a MIME decoder: it does not unwrap `multipart/*`
/// boundaries, does not decode `quoted-printable` or base64 transfer encodings, and does not
/// strip HTML. For the common case of a multipart or base64-encoded message, the excerpt will
/// contain MIME boundary lines and encoded text rather than clean prose. That's a known,
/// accepted limitation of this feature, not a bug — full MIME decoding is a separate, much
/// larger piece of work this app doesn't otherwise need.
nonisolated enum MessageBodyTextExtractor {
    static func excerpt(for message: EmailMessage, maxCharacters: Int = 2000) -> String? {
        let rawData = message.parsed.rawData
        guard message.parsed.bodyOffset < rawData.count else { return nil }
        let bodyBytes = rawData.suffix(from: message.parsed.bodyOffset)
        guard !bodyBytes.isEmpty else { return nil }

        let decoded = EmailHeaderParser.decodeBytes(Array(bodyBytes))
        let trimmed = decoded.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        guard trimmed.count > maxCharacters else { return trimmed }
        return String(trimmed.prefix(maxCharacters)) + "\n…(truncated)"
    }
}
