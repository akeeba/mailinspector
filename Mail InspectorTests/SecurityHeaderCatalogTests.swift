//
//  Mail Inspector
//
//  Copyright (c) 2026 Nicholas K. Dionysopoulos / Akeeba Ltd
//  Licensed under the MIT License. See license.txt in the project root for details.
//

import Testing
import Foundation
@testable import Mail_Inspector

/// Tests for `SecurityHeaderCatalog`: surfacing known mail-filtering headers (spam scores,
/// ARC seals, etc.) with an explanation, while ignoring headers outside the known catalog.
@Suite("SecurityHeaderCatalog")
struct SecurityHeaderCatalogTests {
    @Test("Surfaces known filtering headers with an explanation")
    func surfacesKnownHeaders() throws {
        let raw = "X-Spam-Status: No, score=-2.3\r\nX-Spam-Score: -2.3\r\nARC-Seal: i=1; a=rsa-sha256\r\n\r\n"
        let message = try makeTestMessage(raw)
        let headers = SecurityHeaderCatalog.presentHeaders(in: message.parsed)
        #expect(headers.count == 3)
        #expect(headers.allSatisfy { !$0.explanation.isEmpty })
    }

    @Test("Does not surface headers outside the known catalog")
    func ignoresUnknownHeaders() throws {
        let message = try makeTestMessage("X-Something-Custom: hello\r\n\r\n")
        let headers = SecurityHeaderCatalog.presentHeaders(in: message.parsed)
        #expect(headers.isEmpty)
    }
}
