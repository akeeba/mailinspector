//
//  Mail Inspector
//
//  Copyright (c) 2026 Nicholas K. Dionysopoulos
//  Licensed under the MIT License. See license.txt in the project root for details.
//

import Testing
import Foundation
@testable import Mail_Inspector

/// Tests for `EMLXUnwrapper`: recovering the raw RFC 5322 message from Apple Mail's `.emlx`
/// envelope format (a byte-count line, the message, then a trailing plist), and leaving
/// non-`.emlx` or malformed input unchanged rather than guessing.
@Suite("EMLXUnwrapper")
struct EMLXUnwrapperTests {
    @Test("Recovers the raw RFC 5322 message from an .emlx envelope, discarding the trailing plist")
    func unwrapsEnvelope() {
        let message = "From: a@b.com\r\nSubject: Hi\r\n\r\nBody\r\n"
        let messageData = Data(message.utf8)
        var envelope = Data("\(messageData.count)\n".utf8)
        envelope.append(messageData)
        envelope.append(Data("<?xml version=\"1.0\"?><plist><dict/></plist>".utf8))

        let unwrapped = EMLXUnwrapper.unwrap(envelope)
        #expect(unwrapped == messageData)
    }

    @Test("Leaves data unchanged when it doesn't look like an .emlx envelope")
    func leavesPlainMessageUnchanged() {
        let message = Data("From: a@b.com\r\n\r\nBody\r\n".utf8)
        #expect(EMLXUnwrapper.unwrap(message) == message)
    }

    @Test("Leaves data unchanged when the declared byte count exceeds the available data")
    func rejectsImplausibleByteCount() {
        let malformed = Data("999999\nshort".utf8)
        #expect(EMLXUnwrapper.unwrap(malformed) == malformed)
    }
}
