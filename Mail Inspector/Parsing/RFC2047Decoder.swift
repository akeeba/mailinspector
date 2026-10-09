//
//  Mail Inspector
//
//  Copyright (c) 2026 Nicholas K. Dionysopoulos / Akeeba Ltd
//  Licensed under the MIT License. See license.txt in the project root for details.
//

import Foundation

/// Decodes RFC 2047 encoded-words (`=?charset?B?...?=` / `=?charset?Q?...?=`) that commonly
/// appear in `Subject` and the display-name portion of address headers.
nonisolated enum RFC2047Decoder {
    private static let pattern = try! NSRegularExpression(
        pattern: "=\\?([^?\\s]+)\\?([bBqQ])\\?([^?]*)\\?=",
        options: []
    )

    static func decode(_ input: String) -> String {
        guard input.contains("=?") else { return input }
        let ns = input as NSString
        let fullRange = NSRange(location: 0, length: ns.length)
        let matches = pattern.matches(in: input, options: [], range: fullRange)
        guard !matches.isEmpty else { return input }

        var result = ""
        var lastEnd = 0
        var previousWasEncodedWord = false

        for match in matches {
            let range = match.range
            let between = ns.substring(with: NSRange(location: lastEnd, length: range.location - lastEnd))
            // RFC 2047 §6.2: whitespace separating adjacent encoded-words is not part of the text.
            if !(previousWasEncodedWord && between.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
                result += between
            }

            let charset = ns.substring(with: match.range(at: 1))
            let encodingLetter = ns.substring(with: match.range(at: 2))
            let text = ns.substring(with: match.range(at: 3))
            result += decodeWord(charset: charset, encoding: encodingLetter, text: text) ?? ns.substring(with: range)

            lastEnd = range.location + range.length
            previousWasEncodedWord = true
        }
        result += ns.substring(from: lastEnd)
        return result
    }

    private static func decodeWord(charset: String, encoding: String, text: String) -> String? {
        let bytes: [UInt8]
        switch encoding.uppercased() {
        case "B":
            guard let data = Data(base64Encoded: text, options: .ignoreUnknownCharacters) else { return nil }
            bytes = [UInt8](data)
        case "Q":
            bytes = decodeQEncoding(text)
        default:
            return nil
        }
        let stringEncoding = Self.stringEncoding(forCharset: charset)
        return String(bytes: bytes, encoding: stringEncoding) ?? String(bytes: bytes, encoding: .isoLatin1)
    }

    private static func decodeQEncoding(_ text: String) -> [UInt8] {
        var result: [UInt8] = []
        let chars = Array(text)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c == "_" {
                result.append(0x20)
                i += 1
            } else if c == "=", i + 2 < chars.count,
                      let hi = chars[i + 1].hexDigitValue, let lo = chars[i + 2].hexDigitValue {
                result.append(UInt8(hi * 16 + lo))
                i += 3
            } else {
                result.append(contentsOf: Array(String(c).utf8))
                i += 1
            }
        }
        return result
    }

    private static func stringEncoding(forCharset charset: String) -> String.Encoding {
        let cfEncoding = CFStringConvertIANACharSetNameToEncoding(charset as CFString)
        guard cfEncoding != kCFStringEncodingInvalidId else { return .utf8 }
        let nsEncoding = CFStringConvertEncodingToNSStringEncoding(cfEncoding)
        guard nsEncoding != kCFStringEncodingInvalidId else { return .utf8 }
        return String.Encoding(rawValue: nsEncoding)
    }
}
