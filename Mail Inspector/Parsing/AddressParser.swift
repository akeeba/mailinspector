//
//  Mail Inspector
//
//  Copyright (c) 2026 Nicholas K. Dionysopoulos / Akeeba Ltd
//  Licensed under the MIT License. See license.txt in the project root for details.
//

import Foundation

/// Parses RFC 5322 address headers (`mailbox-list` / `address-list`), handling quoted
/// display names, nested comments, escaped characters, angle-addr, and group syntax.
///
/// Encoded words (RFC 2047) in display names are decoded. Segments that cannot be parsed
/// are preserved as `.malformed` rather than discarded, since malformed input is itself
/// security-relevant.
nonisolated enum AddressParser {
    static func parseAddressList(_ raw: String) -> [AddressListEntry] {
        var scanner = AddressScanner(raw)
        var results: [AddressListEntry] = []
        scanner.skipCFWS()
        while !scanner.isAtEnd {
            let beforeAttempt = scanner.index
            if let entry = scanner.parseAddress() {
                results.append(entry)
            } else {
                let remainder = scanner.captureUntilTopLevelComma().trimmingCharacters(in: .whitespacesAndNewlines)
                if !remainder.isEmpty {
                    results.append(.malformed(raw: remainder))
                }
                if scanner.index == beforeAttempt {
                    // Safety net: guarantee forward progress even on pathological input.
                    scanner.advance()
                }
            }
            scanner.skipCFWS()
            if scanner.peek() == "," {
                scanner.advance()
                scanner.skipCFWS()
            } else {
                break
            }
        }
        return results
    }

    /// Parses a header that is defined to carry a single mailbox (e.g. `Sender`).
    static func parseMailbox(_ raw: String) -> EmailAddress? {
        var scanner = AddressScanner(raw)
        scanner.skipCFWS()
        guard let entry = scanner.parseAddress() else { return nil }
        switch entry {
        case .mailbox(let address): return address
        case .group(_, let members): return members.first
        case .malformed: return nil
        }
    }
}

/// A hand-rolled recursive-descent scanner over RFC 5322 address syntax, operating on
/// `Character` rather than raw bytes since the input has already been decoded to `String`.
nonisolated private struct AddressScanner {
    private let chars: [Character]
    private(set) var index: Int = 0

    init(_ s: String) { chars = Array(s) }

    var isAtEnd: Bool { index >= chars.count }

    func peek() -> Character? { index < chars.count ? chars[index] : nil }

    mutating func advance() { index += 1 }

    mutating func skipCFWS() {
        while let c = peek() {
            if c == " " || c == "\t" || c == "\n" || c == "\r" {
                advance()
            } else if c == "(" {
                skipComment()
            } else {
                break
            }
        }
    }

    /// Skips a parenthesized comment, honoring nesting and backslash escapes.
    mutating func skipComment() {
        guard peek() == "(" else { return }
        advance()
        var depth = 1
        while depth > 0, let c = peek() {
            if c == "\\" {
                advance()
                if !isAtEnd { advance() }
                continue
            }
            if c == "(" { depth += 1 }
            if c == ")" { depth -= 1 }
            advance()
        }
    }

    mutating func readQuotedString() -> String? {
        guard peek() == "\"" else { return nil }
        advance()
        var result = ""
        while let c = peek() {
            if c == "\\" {
                advance()
                if let escaped = peek() {
                    result.append(escaped)
                    advance()
                }
                continue
            }
            if c == "\"" {
                advance()
                return result
            }
            result.append(c)
            advance()
        }
        return result // Unterminated quoted-string; return what was captured rather than fail outright.
    }

    private static let atomSpecials: Set<Character> = Set("()<>[]:;@\\,.\"")

    mutating func readAtom() -> String? {
        var result = ""
        while let c = peek(), !c.isWhitespace, !Self.atomSpecials.contains(c) {
            result.append(c)
            advance()
        }
        return result.isEmpty ? nil : result
    }

    /// `dot-atom = atom *("." atom)`
    mutating func readDotAtom() -> String? {
        guard var result = readAtom() else { return nil }
        while peek() == "." {
            let save = index
            advance()
            if let next = readAtom() {
                result += "." + next
            } else {
                index = save
                break
            }
        }
        return result
    }

    mutating func readDomainLiteral() -> String? {
        guard peek() == "[" else { return nil }
        var result = "["
        advance()
        while let c = peek(), c != "]" {
            if c == "\\" {
                advance()
                if let escaped = peek() { result.append(escaped); advance() }
                continue
            }
            result.append(c)
            advance()
        }
        if peek() == "]" {
            result.append("]")
            advance()
        }
        return result
    }

    /// `phrase = 1*word`, stopping at delimiters that end a display-name context.
    mutating func readPhrase() -> String? {
        var words: [String] = []
        while true {
            skipCFWS()
            guard let c = peek() else { break }
            if c == "<" || c == "@" || c == ":" || c == ";" || c == "," { break }
            if c == "\"" {
                guard let q = readQuotedString() else { break }
                words.append(q)
            } else if let a = readAtom() {
                words.append(a)
            } else {
                break
            }
        }
        return words.isEmpty ? nil : words.joined(separator: " ")
    }

    mutating func readLocalPart() -> String? {
        skipCFWS()
        if peek() == "\"" { return readQuotedString() }
        return readDotAtom()
    }

    mutating func readDomain() -> String? {
        skipCFWS()
        if peek() == "[" { return readDomainLiteral() }
        return readDotAtom()
    }

    mutating func parseAddrSpec() -> EmailAddress? {
        guard let local = readLocalPart() else { return nil }
        skipCFWS()
        guard peek() == "@" else { return nil }
        advance()
        guard let domain = readDomain() else { return nil }
        return EmailAddress(displayName: nil, localPart: local, domain: domain)
    }

    mutating func parseAngleAddr() -> EmailAddress? {
        skipCFWS()
        guard peek() == "<" else { return nil }
        advance()
        skipCFWS()
        guard let addr = parseAddrSpec() else {
            while let c = peek(), c != ">" { advance() }
            if peek() == ">" { advance() }
            return nil
        }
        skipCFWS()
        if peek() == ">" { advance() }
        return addr
    }

    mutating func parseAddress() -> AddressListEntry? {
        let startIndex = index
        skipCFWS()
        let beforePhrase = index
        let phrase = readPhrase()
        skipCFWS()

        if peek() == ":" {
            return parseGroup(displayName: phrase ?? "")
        }

        if peek() == "<" {
            guard var addr = parseAngleAddr() else {
                index = startIndex
                return nil
            }
            if let phrase, !phrase.isEmpty {
                addr.displayName = RFC2047Decoder.decode(phrase)
            }
            return .mailbox(addr)
        }

        // No display-name/angle-addr matched; this may simply be a bare addr-spec.
        index = beforePhrase
        if let addr = parseAddrSpec() {
            return .mailbox(addr)
        }
        index = startIndex
        return nil
    }

    private mutating func parseGroup(displayName: String) -> AddressListEntry {
        advance() // consume ':'
        var members: [EmailAddress] = []
        skipCFWS()
        if peek() == ";" {
            advance()
        } else {
            while !isAtEnd {
                skipCFWS()
                if peek() == ";" {
                    advance()
                    break
                }
                let before = index
                if let entry = parseAddress() {
                    switch entry {
                    case .mailbox(let a): members.append(a)
                    case .group(_, let m): members.append(contentsOf: m)
                    case .malformed: break
                    }
                } else {
                    break
                }
                skipCFWS()
                if peek() == "," {
                    advance()
                } else if peek() == ";" {
                    advance()
                    break
                }
                if index == before { break } // Safety net against pathological input.
            }
        }
        return .group(displayName: RFC2047Decoder.decode(displayName), members: members)
    }

    mutating func captureUntilTopLevelComma() -> String {
        var result = ""
        var depth = 0
        while let c = peek() {
            if c == "(" { depth += 1 }
            if c == ")" { depth = max(0, depth - 1) }
            if c == "," && depth == 0 { break }
            result.append(c)
            advance()
        }
        return result
    }
}
