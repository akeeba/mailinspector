//
//  Mail Inspector
//
//  Copyright (c) 2026 Nicholas K. Dionysopoulos
//  Licensed under the MIT License. See license.txt in the project root for details.
//

import Testing
import Foundation
@testable import Mail_Inspector

/// Tests for `ReceivedSPFParser`: parsing result, client-ip, and envelope-from domain out of
/// a `Received-SPF` header value, including angle-bracket stripping and absent fields.
@Suite("ReceivedSPFParser")
struct ReceivedSPFParserTests {
    @Test("Parses result, client-ip, and envelope-from domain from a Received-SPF value")
    func parsesFields() {
        let value = "pass (google.com: domain of 4schools-info@epafos.gr designates 51.145.238.12 as permitted sender) client-ip=51.145.238.12; envelope-from=4schools-info@epafos.gr;"
        let parsed = ReceivedSPFParser.parse(value)
        #expect(parsed.result == "pass")
        #expect(parsed.clientIP == "51.145.238.12")
        #expect(parsed.envelopeFromDomain == "epafos.gr")
    }

    @Test("Strips angle brackets from an envelope-from address")
    func stripsAngleBrackets() {
        let value = "pass client-ip=1.2.3.4; envelope-from=<user@example.com>;"
        let parsed = ReceivedSPFParser.parse(value)
        #expect(parsed.envelopeFromDomain == "example.com")
    }

    @Test("Returns nil fields when they're absent rather than guessing")
    func missingFieldsAreNil() {
        let parsed = ReceivedSPFParser.parse("none")
        #expect(parsed.result == "none")
        #expect(parsed.clientIP == nil)
        #expect(parsed.envelopeFromDomain == nil)
    }
}
