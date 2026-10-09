//
//  Mail Inspector
//
//  Copyright (c) 2026 Nicholas K. Dionysopoulos / Akeeba Ltd
//  Licensed under the MIT License. See license.txt in the project root for details.
//

import Foundation

/// Looks up a domain's BIMI (Brand Indicators for Message Identification) record and fetches
/// its logo image. Only ever called when the user has opted in via Settings — see
/// `BrandImagePolicy` for the gating decision — since both the DNS lookup and the image fetch
/// are genuine network requests to servers the sender's domain controls.
///
/// Returns raw image `Data`, not a decoded `NSImage` — decoding happens at the SwiftUI call
/// site, which already runs on the main actor, so this type never has to reason about handing
/// a non-`Sendable` AppKit object across an isolation boundary.
///
/// Empirically validated against real published BIMI records (mastercard.com, paypal.com,
/// linkedin.com, chase.com, jpmorgan.com, ebay.com, cnn.com) via `RunCodeSnippet` before being
/// trusted here: the TXT record shape, the `l=`/`a=` tag parsing, and fetching+decoding the
/// resulting SVG via `NSImage(data:)` all confirmed working end to end.
nonisolated enum BrandImageResolver {
    nonisolated struct Record: Sendable, Equatable {
        let logoURL: URL
    }

    /// A conservative cap on the logo payload — BIMI logos are meant to be small, simple SVGs;
    /// anything larger than this is almost certainly not a legitimate logo worth decoding.
    private static let maxImageBytes = 2 * 1024 * 1024

    static func lookupRecord(domain: String) async -> Record? {
        guard !domain.isEmpty else { return nil }
        let queryName = "default._bimi.\(domain)"

        let txtRecords: [String]
        do {
            let answers = try await DNSResolver.queryRaw(queryName, type: .txt, timeoutSeconds: 5)
            txtRecords = answers.map(DNSResolver.decodeTXT).filter { $0.lowercased().hasPrefix("v=bimi1") }
        } catch {
            return nil
        }

        guard let record = txtRecords.first else { return nil }
        let tags = parseTags(record)
        guard let logoString = tags["l"], !logoString.isEmpty,
              let logoURL = URL(string: logoString),
              // BIMI requires HTTPS for the logo URL; refuse anything else outright.
              logoURL.scheme?.lowercased() == "https" else {
            return nil
        }
        return Record(logoURL: logoURL)
    }

    /// Parses a BIMI TXT value's semicolon-separated `tag=value` pairs, e.g.
    /// `v=BIMI1; l=https://example.com/logo.svg; a=https://example.com/cert.pem`.
    static func parseTags(_ record: String) -> [String: String] {
        var result: [String: String] = [:]
        for part in record.split(separator: ";") {
            let keyValue = part.split(separator: "=", maxSplits: 1)
            guard keyValue.count == 2 else { continue }
            let key = keyValue[0].trimmingCharacters(in: .whitespaces).lowercased()
            let value = keyValue[1].trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else { continue }
            result[key] = value
        }
        return result
    }

    /// Fetches the logo's raw bytes. Fails closed on anything unexpected (non-2xx, oversized,
    /// network error) — a missing brand image is never worth surfacing as an error to the user.
    static func fetchImageData(at url: URL) async -> Data? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode),
                  data.count <= maxImageBytes else {
                return nil
            }
            return data
        } catch {
            return nil
        }
    }
}
