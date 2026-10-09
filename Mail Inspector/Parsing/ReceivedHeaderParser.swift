//
//  Mail Inspector
//
//  Copyright (c) 2026 Nicholas K. Dionysopoulos
//  Licensed under the MIT License. See license.txt in the project root for details.
//

import Foundation

/// The result of splitting one `Received:` header into its conventional clauses. Not a formally
/// standardized grammar — MTAs vary — so this is best-effort, and missing pieces are simply nil
/// rather than treated as parse failures.
nonisolated struct ParsedReceivedHeader: Sendable {
    let rawHeaderText: String
    /// The hostname as claimed by the sending side (unverified).
    let claimedFromHostname: String?
    /// The hostname the receiving server found via reverse DNS, if it recorded one, from the
    /// parenthetical remark: `from claimed (verified [ip])`.
    let verifiedFromHostname: String?
    let fromIPAddress: String?
    let byHostname: String?
    let withProtocol: String?
    let tlsVersion: String?
    let tlsCipher: String?
    let timestampRaw: String?
    let timestamp: Date?
    let parseWarnings: [String]
}

/// Parses `Received:` headers' conventional `from ... by ... with ... id ... for ...; date-time`
/// shape. This shape is a long-standing convention, not something RFC 5321/5322 fully specifies,
/// so real-world headers vary; this extracts what it can and leaves the rest nil rather than
/// failing outright.
nonisolated enum ReceivedHeaderParser {
    /// The exact text of the "no from clause" parse warning, exposed so callers (specifically
    /// `DeliveryPathAnalyzer`, for its final-hop exception) can recognize this particular warning
    /// without resorting to fragile substring matching.
    static let missingFromClauseWarning = "This header has no \u{201c}from\u{201d} clause."

    static func parseAll(from parsed: ParsedEmail) -> [ParsedReceivedHeader] {
        parsed.headers(named: "Received").map(parse)
    }

    static func parse(_ field: HeaderField) -> ParsedReceivedHeader {
        let chars = Array(field.unfoldedValue)
        var warnings: [String] = []

        let (clauseChars, timestampRaw) = splitTimestamp(chars)
        let segments = splitClauses(clauseChars)

        let (claimed, verified, ip) = parseFromClause(segments["from"])
        let (tlsVersion, tlsCipher) = extractTLSInfo(field.unfoldedValue)

        var timestamp: Date?
        if let timestampRaw {
            timestamp = EmailDateParser.parse(timestampRaw)
            if timestamp == nil {
                warnings.append("Could not parse the timestamp \u{201c}\(timestampRaw)\u{201d}.")
            }
        } else {
            warnings.append("This header has no recognizable date-time.")
        }

        if segments["from"] == nil {
            warnings.append(missingFromClauseWarning)
        }

        return ParsedReceivedHeader(
            rawHeaderText: field.rawText,
            claimedFromHostname: claimed,
            verifiedFromHostname: verified,
            fromIPAddress: ip,
            byHostname: segments["by"].flatMap(firstToken),
            withProtocol: segments["with"],
            tlsVersion: tlsVersion,
            tlsCipher: tlsCipher,
            timestampRaw: timestampRaw,
            timestamp: timestamp,
            parseWarnings: warnings
        )
    }

    // MARK: - Splitting into clauses

    private static let keywords = ["from", "by", "with", "id", "for"]

    /// Finds the last top-level (outside any parenthetical) semicolon, which conventionally
    /// separates the clauses from the trailing date-time.
    private static func splitTimestamp(_ chars: [Character]) -> (clauses: [Character], timestampRaw: String?) {
        var depth = 0
        var lastSemicolon: Int?
        for i in chars.indices {
            switch chars[i] {
            case "(": depth += 1
            case ")": depth = max(0, depth - 1)
            case ";" where depth == 0: lastSemicolon = i
            default: break
            }
        }
        guard let lastSemicolon else { return (chars, nil) }
        let clauses = Array(chars[0..<lastSemicolon])
        let raw = String(chars[(lastSemicolon + 1)...]).trimmingCharacters(in: .whitespacesAndNewlines)
        return (clauses, raw.isEmpty ? nil : raw)
    }

    /// Finds top-level occurrences of each keyword (outside parentheses, on a word boundary) and
    /// slices the text between consecutive occurrences as that keyword's value.
    private static func splitClauses(_ chars: [Character]) -> [String: String] {
        var occurrences: [(keyword: String, start: Int, end: Int)] = []
        var depth = 0
        var i = 0
        while i < chars.count {
            switch chars[i] {
            case "(":
                depth += 1
            case ")":
                depth = max(0, depth - 1)
            default:
                if depth == 0, i == 0 || chars[i - 1].isWhitespace {
                    for keyword in keywords {
                        let kChars = Array(keyword)
                        guard i + kChars.count <= chars.count, Array(chars[i..<(i + kChars.count)]) == kChars else { continue }
                        let after = i + kChars.count
                        guard after == chars.count || chars[after].isWhitespace else { continue }
                        occurrences.append((keyword, i, after))
                        break
                    }
                }
            }
            i += 1
        }

        var result: [String: String] = [:]
        for (index, occurrence) in occurrences.enumerated() {
            let valueEnd = index + 1 < occurrences.count ? occurrences[index + 1].start : chars.count
            guard occurrence.end < valueEnd else { continue }
            let value = String(chars[occurrence.end..<valueEnd]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty {
                result[occurrence.keyword] = value
            }
        }
        return result
    }

    // MARK: - "from" clause: claimed vs. receiver-verified hostname, and IP

    private static func parseFromClause(_ text: String?) -> (claimed: String?, verified: String?, ip: String?) {
        guard let text, !text.isEmpty else { return (nil, nil, nil) }

        // Only the *first* parenthetical group belongs to the from-clause's reverse-DNS remark
        // (`from claimed (verified [ip])`). Anything after it — e.g. a separate TLS-info remark
        // like `(using TLSv1.3 with cipher ... (256/256 bits))` — is an unrelated annotation and
        // must not be merged into it. Using `firstIndex(of: "(")`/`lastIndex(of: ")")` across the
        // whole clause did exactly that: it spanned from the first paren to the *last* paren of
        // any *later*, unrelated group, swallowing everything in between.
        if let (inner, beforeParen) = firstMatchedParenthetical(in: text) {
            let claimedText = String(text[beforeParen]).trimmingCharacters(in: .whitespaces)
            let (verified, ip) = parseParenthetical(inner)
            let claimed = claimedText.isEmpty ? nil : claimedText
            return (claimed ?? firstToken(text), verified, ip)
        }

        if let ip = extractBracketedAddress(text) {
            return (text.trimmingCharacters(in: .whitespaces), nil, ip)
        }
        return (firstToken(text), nil, nil)
    }

    /// Finds the first `(...)` group, respecting nesting, and returns its inner content plus
    /// the range of text before it. Returns `nil` if there's no parenthetical, or an unclosed
    /// one.
    private static func firstMatchedParenthetical(in text: String) -> (inner: String, beforeParen: Range<String.Index>)? {
        guard let openIndex = text.firstIndex(of: "(") else { return nil }
        var depth = 0
        var index = openIndex
        while index < text.endIndex {
            switch text[index] {
            case "(": depth += 1
            case ")":
                depth -= 1
                if depth == 0 {
                    let inner = String(text[text.index(after: openIndex)..<index])
                    return (inner, text.startIndex..<openIndex)
                }
            default: break
            }
            index = text.index(after: index)
        }
        return nil
    }

    private static func parseParenthetical(_ inner: String) -> (verified: String?, ip: String?) {
        guard let ip = extractBracketedAddress(inner) else {
            let trimmed = inner.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return (nil, nil) }
            // Microsoft/Exchange-style headers annotate the from-clause with the sending host's
            // bare IP in parentheses — e.g. "from host.example (10.1.2.3) by ..." — instead of
            // Postfix's bracketed "(verified [ip])" reverse-DNS remark. A bare IP here is not a
            // reverse-DNS verification result at all, so treating it as the verified hostname
            // produced a false "claimed hostname doesn't match reverse DNS" warning on every hop
            // of this shape.
            if IPAddressClassifier.classify(trimmed) != nil {
                return (nil, trimmed)
            }
            return (trimmed, nil)
        }
        let withoutBracket = inner
            .replacingOccurrences(of: "[\(ip)]", with: "")
            .replacingOccurrences(of: "[IPv6:\(ip)]", with: "", options: .caseInsensitive)
            .trimmingCharacters(in: .whitespaces)
        return (withoutBracket.isEmpty ? nil : withoutBracket, ip)
    }

    private static func extractBracketedAddress(_ text: String?) -> String? {
        guard let text, let open = text.firstIndex(of: "["), let close = text.firstIndex(of: "]"), open < close else {
            return nil
        }
        var address = String(text[text.index(after: open)..<close])
        if address.lowercased().hasPrefix("ipv6:") {
            address = String(address.dropFirst(5))
        }
        return address
    }

    private static func firstToken(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        return trimmed.split(separator: " ").first.map(String.init)
    }

    // MARK: - TLS info

    /// Covers two common styles: `(version=TLS1.3 cipher=AEAD-AES256-GCM-SHA384 bits=256/256)`
    /// (Postfix/Exim-style) and `(using TLSv1.3 with cipher TLS_AES_256_GCM_SHA384 (256/256
    /// bits))` (Dovecot/mailbox.org-style prose).
    private static func extractTLSInfo(_ text: String) -> (version: String?, cipher: String?) {
        if let version = firstMatch(in: text, pattern: "version=([A-Za-z0-9._-]+)"),
           let cipher = firstMatch(in: text, pattern: "cipher=([A-Za-z0-9._-]+)") {
            return (version, cipher)
        }
        let version = firstMatch(in: text, pattern: "using\\s+(TLSv?[0-9.]+)")
        let cipher = firstMatch(in: text, pattern: "cipher\\s+([A-Za-z0-9._-]+)")
        return (version, cipher)
    }

    private static func firstMatch(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let ns = text as NSString
        guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)), match.numberOfRanges > 1 else {
            return nil
        }
        return ns.substring(with: match.range(at: 1))
    }
}
