//
//  Mail Inspector
//
//  Copyright (c) 2026 Nicholas K. Dionysopoulos
//  Licensed under the MIT License. See license.txt in the project root for details.
//

import Testing
import Foundation
@testable import Mail_Inspector

/// Shared test fixture builder: parses raw RFC 5322 source into an `EmailMessage`, used by
/// every suite whose tests need a fully-parsed message rather than raw header-parser output.
func makeTestMessage(_ raw: String) throws -> EmailMessage {
    let parsed = try EmailHeaderParser.parse(data: Data(raw.utf8), maxMessageSize: 10_000_000)
    return EmailMessage(parsed: parsed, sourceDescription: "test.eml")
}
