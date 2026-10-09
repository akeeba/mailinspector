//
//  Mail Inspector
//
//  Copyright (c) 2026 Nicholas K. Dionysopoulos
//  Licensed under the MIT License. See license.txt in the project root for details.
//

import Foundation

/// Parses `DKIM-Signature` headers (RFC 6376 §3.5): a semicolon-separated `tag=value` list.
///
/// This only parses the signature's declared metadata for display — it never attempts to
/// verify the signature (that would require DNS lookups for the public key, which this app does
/// not perform).
nonisolated enum DKIMSignatureParser {
    static func parseAll(from parsed: ParsedEmail) -> [DKIMSignature] {
        parsed.headers(named: "DKIM-Signature").enumerated().map { index, field in
            parse(field, id: index)
        }
    }

    static func parse(_ field: HeaderField, id: Int) -> DKIMSignature {
        var tags: [String: String] = [:]
        for rawTag in field.unfoldedValue.split(separator: ";") {
            guard let equalsIndex = rawTag.firstIndex(of: "=") else { continue }
            let name = rawTag[rawTag.startIndex..<equalsIndex].trimmingCharacters(in: .whitespacesAndNewlines)
            // Tag values may still contain folding whitespace (long base64 blobs are commonly
            // folded); strip all whitespace from the value rather than just trimming the ends.
            let value = rawTag[rawTag.index(after: equalsIndex)...]
                .components(separatedBy: .whitespacesAndNewlines)
                .joined()
            guard !name.isEmpty else { continue }
            tags[name.lowercased()] = value
        }

        let canonicalization = tags["c"]?.split(separator: "/", maxSplits: 1).map(String.init) ?? []

        return DKIMSignature(
            id: id,
            version: tags["v"],
            algorithm: tags["a"],
            headerCanonicalization: canonicalization.first ?? "simple",
            bodyCanonicalization: canonicalization.count > 1 ? canonicalization[1] : "simple",
            signingDomain: tags["d"],
            selector: tags["s"],
            signedHeaders: tags["h"]?.split(separator: ":").map { String($0).trimmingCharacters(in: .whitespaces) } ?? [],
            timestamp: tags["t"].flatMap(Self.date(fromEpochSeconds:)),
            expiration: tags["x"].flatMap(Self.date(fromEpochSeconds:)),
            identity: tags["i"],
            rawTags: tags,
            rawHeaderText: field.rawText
        )
    }

    private static func date(fromEpochSeconds string: String) -> Date? {
        guard let seconds = TimeInterval(string) else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }
}
