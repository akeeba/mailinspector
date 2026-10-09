//
//  Mail Inspector
//
//  Copyright (c) 2026 Nicholas K. Dionysopoulos / Akeeba Ltd
//  Licensed under the MIT License. See license.txt in the project root for details.
//

import Foundation

/// A single header field as it appeared in the message.
///
/// Both the original raw text (preserving folding) and an unfolded value (suitable for
/// further parsing) are retained, per the requirement to never silently discard the
/// original representation of a header.
nonisolated struct HeaderField: Sendable, Equatable, Identifiable {
    let id: Int
    /// The field name exactly as it appeared before the colon (original casing).
    let name: String
    /// The original text of the field, including folded continuation lines joined by "\n".
    let rawText: String
    /// The value with CRLF folding removed, suitable for semantic parsing.
    let unfoldedValue: String
}

/// The result of splitting a raw RFC 5322 message into its header fields and body offset,
/// without decoding or rendering the body.
nonisolated struct ParsedEmail: Sendable {
    let headers: [HeaderField]
    /// Byte offset into `rawData` where the message body begins.
    let bodyOffset: Int
    /// Non-fatal issues encountered while parsing (malformed folding, missing header/body
    /// separator, header lines without a colon, etc).
    let warnings: [String]
    let rawData: Data

    func headers(named name: String) -> [HeaderField] {
        headers.filter { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    func firstHeader(named name: String) -> HeaderField? {
        headers.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    /// The complete original header block, decoded leniently, exactly as received.
    var rawHeaderText: String {
        EmailHeaderParser.decodeBytes(Array(rawData.prefix(bodyOffset)))
    }
}

nonisolated enum EmailParsingError: Error, Sendable, Equatable {
    case empty
    case messageTooLarge(limit: Int)
}

/// Splits raw RFC 5322 message bytes into header fields and a body offset.
///
/// Operates on raw bytes (not `String`) so that non-UTF-8 and binary messages never cause a
/// decoding failure: header text that isn't valid UTF-8 falls back to ISO Latin-1, which can
/// represent any byte sequence.
nonisolated enum EmailHeaderParser {
    static func parse(data: Data, maxMessageSize: Int) throws -> ParsedEmail {
        guard !data.isEmpty else { throw EmailParsingError.empty }
        guard data.count <= maxMessageSize else { throw EmailParsingError.messageTooLarge(limit: maxMessageSize) }

        var warnings: [String] = []
        let bytes = [UInt8](data)
        let cr: UInt8 = 0x0D
        let lf: UInt8 = 0x0A

        var lineRanges: [(start: Int, end: Int)] = []
        var headerEnd: Int?
        var i = 0
        while i < bytes.count {
            var j = i
            while j < bytes.count, bytes[j] != lf { j += 1 }
            if j >= bytes.count {
                lineRanges.append((start: i, end: bytes.count))
                warnings.append("Message ends without a final line terminator.")
                break
            }
            var lineEnd = j
            if lineEnd > i, bytes[lineEnd - 1] == cr {
                lineEnd -= 1
            }
            lineRanges.append((start: i, end: lineEnd))
            if lineEnd == i {
                headerEnd = j + 1
                break
            }
            i = j + 1
        }

        guard let bodyStart = headerEnd else {
            warnings.append("No blank line found separating headers from body; treating the entire message as headers.")
            let headers = foldLines(lineRanges, bytes: bytes, warnings: &warnings)
            return ParsedEmail(headers: headers, bodyOffset: bytes.count, warnings: warnings, rawData: data)
        }

        var headerLineRanges = lineRanges
        if let last = headerLineRanges.last, last.start == last.end {
            headerLineRanges.removeLast()
        }
        let headers = foldLines(headerLineRanges, bytes: bytes, warnings: &warnings)
        return ParsedEmail(headers: headers, bodyOffset: bodyStart, warnings: warnings, rawData: data)
    }

    private static func foldLines(
        _ lines: [(start: Int, end: Int)],
        bytes: [UInt8],
        warnings: inout [String]
    ) -> [HeaderField] {
        var fields: [HeaderField] = []
        var idx = 0
        var nextID = 0
        while idx < lines.count {
            let line = lines[idx]
            if line.start == line.end {
                idx += 1
                continue
            }
            if bytes[line.start] == 0x20 || bytes[line.start] == 0x09 {
                warnings.append("Found a folded continuation line with no preceding header field; ignoring it.")
                idx += 1
                continue
            }
            guard let colonPos = (line.start..<line.end).first(where: { bytes[$0] == 0x3A }) else {
                warnings.append("Header line without a colon encountered; preserved as a malformed field.")
                let raw = decodeBytes(Array(bytes[line.start..<line.end]))
                fields.append(HeaderField(id: nextID, name: "", rawText: raw, unfoldedValue: raw))
                nextID += 1
                idx += 1
                continue
            }

            let name = decodeBytes(Array(bytes[line.start..<colonPos])).trimmingCharacters(in: .whitespaces)
            let valueStart = colonPos + 1

            var rawRanges: [(Int, Int)] = [(line.start, line.end)]
            var j = idx + 1
            while j < lines.count {
                let next = lines[j]
                if next.start < next.end, (bytes[next.start] == 0x20 || bytes[next.start] == 0x09) {
                    rawRanges.append((next.start, next.end))
                    j += 1
                } else {
                    break
                }
            }
            idx = j

            let rawText = rawRanges.map { decodeBytes(Array(bytes[$0.0..<$0.1])) }.joined(separator: "\n")

            var unfolded = ""
            for (k, range) in rawRanges.enumerated() {
                let start = k == 0 ? valueStart : range.0
                unfolded += decodeBytes(Array(bytes[start..<range.1]))
            }
            if unfolded.first == " " || unfolded.first == "\t" {
                unfolded.removeFirst()
            }

            fields.append(HeaderField(id: nextID, name: name, rawText: rawText, unfoldedValue: unfolded))
            nextID += 1
        }
        return fields
    }

    /// Decodes bytes as UTF-8, falling back to ISO Latin-1 (which can represent any byte
    /// sequence) so malformed or legacy-encoded headers never cause a parsing failure.
    static func decodeBytes(_ bytes: [UInt8]) -> String {
        guard !bytes.isEmpty else { return "" }
        if let s = String(bytes: bytes, encoding: .utf8) {
            return s
        }
        return String(bytes: bytes, encoding: .isoLatin1) ?? ""
    }
}
