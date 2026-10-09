//
//  Mail Inspector
//
//  Copyright (c) 2026 Nicholas K. Dionysopoulos
//  Licensed under the MIT License. See license.txt in the project root for details.
//

import Testing
import Foundation
@testable import Mail_Inspector

/// Tests for `RFC2047Decoder`: decoding Base64 (B) and quoted-printable (Q) encoded words,
/// and leaving plain or adjacent-encoded text handled correctly.
@Suite("RFC2047Decoder")
struct RFC2047DecoderTests {
    @Test("Decodes a Base64 (B) encoded word")
    func base64Word() {
        #expect(RFC2047Decoder.decode("=?UTF-8?B?SGVsbG8=?=") == "Hello")
    }

    @Test("Decodes a quoted-printable (Q) encoded word, including underscore as space")
    func quotedPrintableWord() {
        #expect(RFC2047Decoder.decode("=?UTF-8?Q?Hello_World?=") == "Hello World")
    }

    @Test("Leaves plain text without encoded words untouched")
    func plainText() {
        #expect(RFC2047Decoder.decode("Plain Subject") == "Plain Subject")
    }

    @Test("Joins adjacent encoded words without the intervening whitespace")
    func adjacentEncodedWords() {
        let decoded = RFC2047Decoder.decode("=?UTF-8?Q?Hello?= =?UTF-8?Q?World?=")
        #expect(decoded == "HelloWorld")
    }
}
