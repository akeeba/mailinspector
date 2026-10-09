//
//  Mail Inspector
//
//  Copyright (c) 2026 Nicholas K. Dionysopoulos
//  Licensed under the MIT License. See license.txt in the project root for details.
//

import Testing
import Foundation
@testable import Mail_Inspector

/// Tests for `MessageBodyTextExtractor`: a best-effort, non-MIME-aware decode of a message's
/// body, used only when the user explicitly attaches it to an Apple Intelligence chat question.
@Suite("MessageBodyTextExtractor")
struct MessageBodyTextExtractorTests {
    @Test("Passes a short plain body through unchanged, trimmed of surrounding whitespace")
    func passesShortBodyThrough() throws {
        let message = try makeTestMessage("Subject: Test\r\n\r\nHello, this is the body.\r\n")
        #expect(MessageBodyTextExtractor.excerpt(for: message) == "Hello, this is the body.")
    }

    @Test("Truncates a body longer than the character limit, with a trailing marker")
    func truncatesLongBody() throws {
        let longBody = String(repeating: "a", count: 50)
        let message = try makeTestMessage("Subject: Test\r\n\r\n\(longBody)")
        let excerpt = try #require(MessageBodyTextExtractor.excerpt(for: message, maxCharacters: 10))
        #expect(excerpt == String(repeating: "a", count: 10) + "\n…(truncated)")
    }

    @Test("Returns nil when the message has no body at all")
    func returnsNilForMissingBody() throws {
        let message = try makeTestMessage("Subject: Test\r\n\r\n")
        #expect(MessageBodyTextExtractor.excerpt(for: message) == nil)
    }

    @Test("Returns nil when there's no blank line separating headers from body, so the whole message was treated as headers")
    func returnsNilWhenNoBodySeparator() throws {
        let message = try makeTestMessage("Subject: Test")
        #expect(MessageBodyTextExtractor.excerpt(for: message) == nil)
    }
}
