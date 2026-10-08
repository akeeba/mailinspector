import Foundation

/// Parses `Authentication-Results` headers per RFC 8601.
///
/// Comments (parenthesized text, e.g. `spf=pass (sender SPF authorized)`) are preserved as the
/// `reason` for the nearest preceding method result when no explicit `reason=` tag is present,
/// since in practice that's where most servers put their human-readable explanation.
nonisolated enum AuthenticationResultsParser {
    /// Parses every `Authentication-Results` header on the message, preserving header order and
    /// never collapsing repeated headers — each one may have been added by a different hop.
    static func parseAll(from parsed: ParsedEmail) -> [AuthenticationResultsHeader] {
        parsed.headers(named: "Authentication-Results").enumerated().map { index, field in
            parse(field, id: index)
        }
    }

    static func parse(_ field: HeaderField, id: Int) -> AuthenticationResultsHeader {
        var scanner = AuthResultsScanner(field.unfoldedValue)
        scanner.skipCFWS()

        let authServID = scanner.readToken() ?? ""
        scanner.skipCFWS()
        let authServVersion = scanner.peekIsDigit() ? scanner.readToken() : nil

        var results: [AuthMethodResult] = []
        var nextResultID = 0

        while true {
            scanner.skipCFWS()
            guard scanner.consume(";") else { break }
            scanner.skipCFWS()
            if scanner.isAtEnd { break }

            // A bare "none" resinfo means nothing was authenticated for this identity at all.
            if scanner.peekKeyword("none") {
                _ = scanner.readToken()
                continue
            }

            guard let method = scanner.readToken() else { break }
            var methodVersion: String?
            if scanner.consume("/") {
                methodVersion = scanner.readToken()
            }
            scanner.skipCFWS()
            guard scanner.consume("=") else { continue }
            scanner.skipCFWS()
            guard let result = scanner.readValue() else { continue }

            var reason: String?
            var properties: [AuthProperty] = []
            var trailingComments: [String] = []

            while true {
                let comments = scanner.skipCFWS()
                trailingComments.append(contentsOf: comments)
                guard let peeked = scanner.peekNonDelimiter(), peeked != ";" else { break }

                let savedIndex = scanner.index
                guard let key = scanner.readToken() else { break }
                if key.caseInsensitiveCompare("reason") == .orderedSame {
                    scanner.skipCFWS()
                    if scanner.consume("=") {
                        scanner.skipCFWS()
                        reason = scanner.readValue()
                    }
                } else if key.contains(".") {
                    let parts = key.split(separator: ".", maxSplits: 1)
                    let ptype = String(parts.first ?? "")
                    let property = parts.count > 1 ? String(parts[1]) : ""
                    scanner.skipCFWS()
                    if scanner.consume("=") {
                        scanner.skipCFWS()
                        if let value = scanner.readValue() {
                            properties.append(AuthProperty(ptype: ptype, property: property, value: value))
                        }
                    }
                } else {
                    // Unrecognized bare token (not a known key=value shape): stop so it can be
                    // re-examined as the start of the next resinfo rather than silently consumed.
                    scanner.index = savedIndex
                    break
                }
            }

            results.append(AuthMethodResult(
                id: nextResultID,
                method: method.lowercased(),
                methodVersion: methodVersion,
                result: result.lowercased(),
                reason: reason ?? trailingComments.first,
                properties: properties
            ))
            nextResultID += 1
        }

        return AuthenticationResultsHeader(
            id: id,
            authServID: authServID,
            authServVersion: authServVersion,
            results: results,
            rawHeaderText: field.rawText
        )
    }
}

/// Character-level scanner for RFC 8601 `Authentication-Results` syntax.
nonisolated private struct AuthResultsScanner {
    private let chars: [Character]
    var index: Int = 0

    init(_ s: String) { chars = Array(s) }

    var isAtEnd: Bool { index >= chars.count }

    private func peek() -> Character? { index < chars.count ? chars[index] : nil }

    private mutating func advance() { index += 1 }

    /// Skips whitespace and comments, returning the text of any comments encountered (without
    /// the enclosing parentheses) so callers can attach them as an explanation.
    mutating func skipCFWS() -> [String] {
        var comments: [String] = []
        while let c = peek() {
            if c == " " || c == "\t" || c == "\n" || c == "\r" {
                advance()
            } else if c == "(" {
                comments.append(readComment())
            } else {
                break
            }
        }
        return comments
    }

    private mutating func readComment() -> String {
        advance() // consume '('
        var result = ""
        var depth = 1
        while depth > 0, let c = peek() {
            if c == "\\" {
                advance()
                if let escaped = peek() { result.append(escaped); advance() }
                continue
            }
            if c == "(" { depth += 1 }
            if c == ")" {
                depth -= 1
                if depth == 0 { advance(); break }
            }
            result.append(c)
            advance()
        }
        return result
    }

    mutating func consume(_ c: Character) -> Bool {
        guard peek() == c else { return false }
        advance()
        return true
    }

    func peekIsDigit() -> Bool {
        guard let c = peek() else { return false }
        return c.isNumber
    }

    func peekNonDelimiter() -> Character? {
        guard let c = peek(), c != ";" else { return peek() }
        return c
    }

    func peekKeyword(_ keyword: String) -> Bool {
        let candidate = chars[index...].prefix(keyword.count)
        guard candidate.count == keyword.count, String(candidate).caseInsensitiveCompare(keyword) == .orderedSame else {
            return false
        }
        let after = index + keyword.count
        if after < chars.count {
            let next = chars[after]
            return next == " " || next == "\t" || next == ";" || next == "\n" || next == "\r"
        }
        return true
    }

    private static let tokenDelimiters: Set<Character> = Set(" \t\r\n=;(\"")

    /// Reads a bare token: a method name, result keyword, authserv-id, version number, or
    /// `ptype.property` key — anything that isn't a quoted-string.
    mutating func readToken() -> String? {
        var result = ""
        while let c = peek(), !Self.tokenDelimiters.contains(c) {
            result.append(c)
            advance()
        }
        return result.isEmpty ? nil : result
    }

    /// Reads a value: either a quoted-string or a bare token.
    mutating func readValue() -> String? {
        if peek() == "\"" {
            return readQuotedString()
        }
        return readToken()
    }

    private mutating func readQuotedString() -> String {
        advance() // consume opening quote
        var result = ""
        while let c = peek() {
            if c == "\\" {
                advance()
                if let escaped = peek() { result.append(escaped); advance() }
                continue
            }
            if c == "\"" {
                advance()
                break
            }
            result.append(c)
            advance()
        }
        return result
    }
}
