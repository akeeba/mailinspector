//
//  Mail Inspector
//
//  Copyright (c) 2026 Nicholas K. Dionysopoulos
//  Licensed under the MIT License. See license.txt in the project root for details.
//

import Foundation

/// Parses the RFC 5322 `Date` header, tolerating the many non-conformant variants seen in
/// real-world and deliberately malformed mail.
nonisolated enum EmailDateParser {
    private static let formatters: [DateFormatter] = {
        let formats = [
            "EEE, d MMM yyyy HH:mm:ss Z",
            "EEE, d MMM yyyy HH:mm:ss zzz",
            "d MMM yyyy HH:mm:ss Z",
            "EEE, d MMM yy HH:mm:ss Z",
            "d MMM yy HH:mm:ss Z",
            "EEE, d MMM yyyy HH:mm Z",
            "d MMM yyyy HH:mm Z"
        ]
        return formats.map { format in
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = format
            formatter.timeZone = TimeZone(identifier: "UTC")
            return formatter
        }
    }()

    static func parse(_ raw: String) -> Date? {
        let withoutComment = stripTrailingComment(raw.trimmingCharacters(in: .whitespacesAndNewlines))
        for formatter in formatters {
            if let date = formatter.date(from: withoutComment) {
                return date
            }
        }
        return nil
    }

    private static func stripTrailingComment(_ s: String) -> String {
        guard let parenIndex = s.firstIndex(of: "(") else { return s }
        return String(s[s.startIndex..<parenIndex]).trimmingCharacters(in: .whitespaces)
    }
}
