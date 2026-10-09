//
//  Mail Inspector
//
//  Copyright (c) 2026 Nicholas K. Dionysopoulos / Akeeba Ltd
//  Licensed under the MIT License. See license.txt in the project root for details.
//

import Foundation

/// Apple Mail stores messages on disk as `.emlx`: a leading ASCII line giving the byte length of
/// the embedded RFC 5322 message, the message bytes themselves, then a trailing property list of
/// Mail-internal flags. Dragging a message from Mail's list can hand us a direct file URL to one
/// of these `.emlx` files rather than a plain `.eml`, so this recovers the raw message bytes.
nonisolated enum EMLXUnwrapper {
    static func unwrap(_ data: Data) -> Data {
        guard let newline = data.firstIndex(of: 0x0A) else { return data }
        let countBytes = data[data.startIndex..<newline]
        guard let countString = String(bytes: countBytes, encoding: .ascii),
              let count = Int(countString.trimmingCharacters(in: .whitespaces)),
              count > 0 else {
            return data
        }
        let messageStart = data.index(after: newline)
        guard let messageEnd = data.index(messageStart, offsetBy: count, limitedBy: data.endIndex),
              messageStart < messageEnd else {
            return data
        }
        return data.subdata(in: messageStart..<messageEnd)
    }
}
