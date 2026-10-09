//
//  Mail Inspector
//
//  Copyright (c) 2026 Nicholas K. Dionysopoulos
//  Licensed under the MIT License. See license.txt in the project root for details.
//

import Testing
import Foundation
@testable import Mail_Inspector

/// Tests for `DKIMSignatureParser`: parsing RFC 6376 `DKIM-Signature` headers — signing
/// domain, selector, algorithm, canonicalization defaults, signed-header list, timestamps,
/// and folded/multi-line tag values.
@Suite("DKIMSignatureParser")
struct DKIMSignatureParserTests {
    @Test("Parses signing domain, selector, algorithm, canonicalization, signed headers, and timestamps")
    func parsesSignature() throws {
        let raw = "DKIM-Signature: v=1; a=rsa-sha256; c=relaxed/simple; d=example.com; s=selector1;\r\n" +
            " h=from:to:subject:date; t=1700000000; x=1700600000;\r\n" +
            " bh=abc123==; b=def456\r\n   ==more\r\n\r\n"
        let message = try makeTestMessage(raw)
        let signatures = DKIMSignatureParser.parseAll(from: message.parsed)
        #expect(signatures.count == 1)
        let sig = signatures[0]
        #expect(sig.signingDomain == "example.com")
        #expect(sig.selector == "selector1")
        #expect(sig.algorithm == "rsa-sha256")
        #expect(sig.headerCanonicalization == "relaxed")
        #expect(sig.bodyCanonicalization == "simple")
        #expect(sig.signedHeaders == ["from", "to", "subject", "date"])
        #expect(sig.timestamp == Date(timeIntervalSince1970: 1_700_000_000))
        #expect(sig.expiration == Date(timeIntervalSince1970: 1_700_600_000))
        #expect(sig.rawTags["b"] == "def456==more")
    }

    @Test("Defaults canonicalization to simple/simple when c= is absent")
    func defaultsCanonicalization() throws {
        let raw = "DKIM-Signature: v=1; a=rsa-sha256; d=example.com; s=sel; h=from; bh=x; b=y\r\n\r\n"
        let message = try makeTestMessage(raw)
        let sig = DKIMSignatureParser.parseAll(from: message.parsed)[0]
        #expect(sig.headerCanonicalization == "simple")
        #expect(sig.bodyCanonicalization == "simple")
    }
}
