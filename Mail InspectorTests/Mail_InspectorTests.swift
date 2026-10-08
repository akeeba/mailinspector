import Testing
import Foundation
@testable import Mail_Inspector

@Suite("EmailHeaderParser")
struct EmailHeaderParserTests {
    @Test("Splits a simple CRLF message into headers and body without touching the body")
    func basicCRLFMessage() throws {
        let raw = "From: alice@example.com\r\nTo: bob@example.com\r\nSubject: Hello\r\n\r\nThis is the body.\r\n"
        let data = Data(raw.utf8)
        let parsed = try EmailHeaderParser.parse(data: data, maxMessageSize: 1_000_000)

        #expect(parsed.headers.count == 3)
        #expect(parsed.firstHeader(named: "from")?.unfoldedValue == "alice@example.com")
        #expect(parsed.firstHeader(named: "SUBJECT")?.unfoldedValue == "Hello")
        let body = String(decoding: data.suffix(from: parsed.bodyOffset), as: UTF8.self)
        #expect(body == "This is the body.\r\n")
    }

    @Test("Handles bare LF line endings")
    func bareLFMessage() throws {
        let raw = "From: alice@example.com\nSubject: Hi\n\nBody text\n"
        let parsed = try EmailHeaderParser.parse(data: Data(raw.utf8), maxMessageSize: 1_000_000)
        #expect(parsed.firstHeader(named: "From")?.unfoldedValue == "alice@example.com")
        #expect(parsed.firstHeader(named: "Subject")?.unfoldedValue == "Hi")
    }

    @Test("Unfolds a header continued across multiple lines")
    func foldedHeader() throws {
        let raw = "Subject: This is a\r\n very long\r\n\tsubject line\r\n\r\nBody\r\n"
        let parsed = try EmailHeaderParser.parse(data: Data(raw.utf8), maxMessageSize: 1_000_000)
        let subject = parsed.firstHeader(named: "Subject")
        #expect(subject?.unfoldedValue == "This is a very long\tsubject line")
        #expect(subject?.rawText.contains("\n") == true)
    }

    @Test("Preserves repeated headers instead of discarding duplicates")
    func repeatedHeaders() throws {
        let raw = "Received: hop1\r\nReceived: hop2\r\nFrom: a@b.com\r\n\r\n"
        let parsed = try EmailHeaderParser.parse(data: Data(raw.utf8), maxMessageSize: 1_000_000)
        #expect(parsed.headers(named: "Received").count == 2)
    }

    @Test("Matches header names case-insensitively")
    func caseInsensitiveNames() throws {
        let raw = "FROM: a@b.com\r\n\r\n"
        let parsed = try EmailHeaderParser.parse(data: Data(raw.utf8), maxMessageSize: 1_000_000)
        #expect(parsed.firstHeader(named: "from") != nil)
        #expect(parsed.firstHeader(named: "From") != nil)
    }

    @Test("Records a warning and keeps going when no header/body separator exists")
    func missingBodySeparator() throws {
        let raw = "From: a@b.com\r\nSubject: no body separator"
        let parsed = try EmailHeaderParser.parse(data: Data(raw.utf8), maxMessageSize: 1_000_000)
        #expect(!parsed.warnings.isEmpty)
        #expect(parsed.firstHeader(named: "From")?.unfoldedValue == "a@b.com")
    }

    @Test("Preserves a header line with no colon as a malformed field rather than discarding it")
    func headerLineWithoutColon() throws {
        let raw = "From: a@b.com\r\nThis line has no colon\r\nSubject: Hi\r\n\r\nBody\r\n"
        let parsed = try EmailHeaderParser.parse(data: Data(raw.utf8), maxMessageSize: 1_000_000)
        #expect(parsed.headers.contains { $0.rawText == "This line has no colon" })
        #expect(parsed.firstHeader(named: "Subject")?.unfoldedValue == "Hi")
    }

    @Test("Falls back to Latin-1 for non-UTF-8 header bytes instead of failing")
    func nonUTF8Bytes() throws {
        var bytes = Array("Subject: ".utf8)
        bytes.append(0xE9) // invalid standalone UTF-8 continuation byte
        bytes.append(contentsOf: Array("\r\n\r\n".utf8))
        let parsed = try EmailHeaderParser.parse(data: Data(bytes), maxMessageSize: 1_000_000)
        #expect(parsed.firstHeader(named: "Subject") != nil)
    }

    @Test("Rejects a message larger than the configured maximum size")
    func messageTooLarge() {
        let raw = Data(repeating: 0x41, count: 100)
        #expect(throws: EmailParsingError.self) {
            try EmailHeaderParser.parse(data: raw, maxMessageSize: 10)
        }
    }

    @Test("Rejects empty input")
    func emptyInput() {
        #expect(throws: EmailParsingError.self) {
            try EmailHeaderParser.parse(data: Data(), maxMessageSize: 1_000_000)
        }
    }

    @Test("Handles an unusually large but within-limit message without crashing")
    func largeMessage() throws {
        let filler = String(repeating: "X", count: 500_000)
        let raw = "From: a@b.com\r\nSubject: \(filler)\r\n\r\nBody\r\n"
        let parsed = try EmailHeaderParser.parse(data: Data(raw.utf8), maxMessageSize: 10_000_000)
        #expect(parsed.firstHeader(named: "Subject")?.unfoldedValue.count == filler.count)
    }
}

@Suite("AddressParser")
struct AddressParserTests {
    @Test("Parses a simple angle-addr mailbox with display name")
    func displayNameAndAngleAddr() {
        let entries = AddressParser.parseAddressList("Alice Example <alice@example.com>")
        guard case .mailbox(let address) = entries.first else {
            Issue.record("Expected a mailbox entry")
            return
        }
        #expect(address.displayName == "Alice Example")
        #expect(address.address == "alice@example.com")
    }

    @Test("Parses a bare addr-spec with no display name")
    func bareAddrSpec() {
        let entries = AddressParser.parseAddressList("alice@example.com")
        guard case .mailbox(let address) = entries.first else {
            Issue.record("Expected a mailbox entry")
            return
        }
        #expect(address.displayName == nil)
        #expect(address.address == "alice@example.com")
    }

    @Test("Parses a quoted display name that itself contains an email address, surfacing the mismatch")
    func quotedDisplayNameContainingAddress() {
        let entries = AddressParser.parseAddressList("\"support@bank.com\" <attacker@evil.example>")
        guard case .mailbox(let address) = entries.first else {
            Issue.record("Expected a mailbox entry")
            return
        }
        #expect(address.displayName == "support@bank.com")
        #expect(address.address == "attacker@evil.example")
    }

    @Test("Parses a comma-separated address list")
    func multipleAddresses() {
        let entries = AddressParser.parseAddressList("a@b.com, Bob <bob@c.com>, \"Carol C\" <carol@d.com>")
        #expect(entries.count == 3)
    }

    @Test("Skips comments embedded in an address")
    func addressWithComment() {
        let entries = AddressParser.parseAddressList("alice@example.com (this is a comment)")
        guard case .mailbox(let address) = entries.first else {
            Issue.record("Expected a mailbox entry")
            return
        }
        #expect(address.address == "alice@example.com")
    }

    @Test("Parses group syntax and flattens its members")
    func groupSyntax() {
        let entries = AddressParser.parseAddressList("Undisclosed: a@b.com, c@d.com;")
        guard case .group(let name, let members) = entries.first else {
            Issue.record("Expected a group entry")
            return
        }
        #expect(name == "Undisclosed")
        #expect(members.map(\.address) == ["a@b.com", "c@d.com"])
    }

    @Test("Preserves an unparseable segment as malformed instead of silently dropping it")
    func malformedSegmentPreserved() {
        let entries = AddressParser.parseAddressList("not an address, bob@example.com")
        #expect(entries.contains { if case .malformed = $0 { return true } else { return false } })
        #expect(entries.contains { if case .mailbox(let a) = $0 { return a.address == "bob@example.com" } else { return false } })
    }

    @Test("Decodes an RFC 2047 encoded display name")
    func encodedWordDisplayName() {
        let entries = AddressParser.parseAddressList("=?UTF-8?B?zp3Or866zr/Pgg==?= <test@example.com>")
        guard case .mailbox(let address) = entries.first else {
            Issue.record("Expected a mailbox entry")
            return
        }
        #expect(address.displayName == "Νίκος")
    }

    @Test("Parses an IDN/Punycode domain as an ordinary domain token")
    func punycodeDomain() {
        let entries = AddressParser.parseAddressList("user@xn--mnich-kva.example")
        guard case .mailbox(let address) = entries.first else {
            Issue.record("Expected a mailbox entry")
            return
        }
        #expect(address.domain == "xn--mnich-kva.example")
    }
}

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

@Suite("EmailMessage")
struct EmailMessageTests {
    private func makeMessage(_ raw: String) throws -> EmailMessage {
        let parsed = try EmailHeaderParser.parse(data: Data(raw.utf8), maxMessageSize: 10_000_000)
        return EmailMessage(parsed: parsed, sourceDescription: "test.eml")
    }

    @Test("Exposes the complete From address and decoded display name")
    func fromAddress() throws {
        let message = try makeMessage("From: \"Alice Example\" <alice@example.com>\r\nSubject: Hi\r\n\r\n")
        #expect(message.primaryFrom?.address == "alice@example.com")
        #expect(message.primaryFrom?.displayName == "Alice Example")
    }

    @Test("Flags multiple From headers rather than silently picking one")
    func duplicateFromHeaders() throws {
        let message = try makeMessage("From: a@b.com\r\nFrom: c@d.com\r\n\r\n")
        #expect(message.fromHeaderCount == 2)
    }

    @Test("Detects a Reply-To domain that differs from the From domain")
    func replyToMismatch() throws {
        let message = try makeMessage("From: billing@bank.example\r\nReply-To: attacker@evil.example\r\n\r\n")
        let fromDomain = message.primaryFrom?.domain
        let replyToDomain: String? = {
            guard case .mailbox(let address) = message.replyToEntries.first else { return nil }
            return address.domain
        }()
        #expect(fromDomain != replyToDomain)
    }

    @Test("Detects a Return-Path domain that differs from the From domain")
    func returnPathMismatch() throws {
        let message = try makeMessage("From: billing@bank.example\r\nReturn-Path: <bounce@othermailer.example>\r\n\r\n")
        #expect(message.returnPath?.contains("othermailer.example") == true)
        #expect(message.primaryFrom?.domain == "bank.example")
    }

    @Test("Decodes an RFC 2047 encoded Subject")
    func encodedSubject() throws {
        let message = try makeMessage("Subject: =?UTF-8?B?SGVsbG8=?=\r\n\r\n")
        #expect(message.subject == "Hello")
    }

    @Test("Parses a standard RFC 5322 Date header")
    func parsedDate() throws {
        let message = try makeMessage("Date: Mon, 2 Jan 2006 15:04:05 +0000\r\n\r\n")
        #expect(message.date != nil)
    }

    @Test("Never exposes or evaluates the message body as headers")
    func bodyNeverTreatedAsHeaders() throws {
        let raw = "From: a@b.com\r\n\r\n<script>alert(1)</script>\r\nFrom: injected@evil.example\r\n"
        let message = try makeMessage(raw)
        #expect(message.fromHeaderCount == 1)
    }
}

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

private func makeTestMessage(_ raw: String) throws -> EmailMessage {
    let parsed = try EmailHeaderParser.parse(data: Data(raw.utf8), maxMessageSize: 10_000_000)
    return EmailMessage(parsed: parsed, sourceDescription: "test.eml")
}

@Suite("AuthenticationResultsParser")
struct AuthenticationResultsParserTests {
    @Test("Parses authserv-id and multiple method results with properties")
    func parsesBasicHeader() throws {
        let raw = "Authentication-Results: mx.google.com;\r\n" +
            " spf=pass smtp.mailfrom=sender@example.com;\r\n" +
            " dkim=pass header.d=example.com header.s=selector1;\r\n" +
            " dmarc=pass header.from=example.com\r\n\r\n"
        let message = try makeTestMessage(raw)
        let headers = AuthenticationResultsParser.parseAll(from: message.parsed)
        #expect(headers.count == 1)
        let header = headers[0]
        #expect(header.authServID == "mx.google.com")
        #expect(header.results.count == 3)
        #expect(header.results[0].method == "spf")
        #expect(header.results[0].result == "pass")
        #expect(header.results[0].property(ptype: "smtp", "mailfrom") == "sender@example.com")
        #expect(header.results[1].property(ptype: "header", "d") == "example.com")
        #expect(header.results[1].property(ptype: "header", "s") == "selector1")
    }

    @Test("Parses a comment as the reason when no explicit reason tag is present")
    func parsesCommentAsReason() throws {
        let raw = "Authentication-Results: mx.example.com; spf=softfail (sender IP not in SPF record) smtp.mailfrom=a@b.com\r\n\r\n"
        let message = try makeTestMessage(raw)
        let header = AuthenticationResultsParser.parseAll(from: message.parsed)[0]
        #expect(header.results[0].result == "softfail")
        #expect(header.results[0].reason == "sender IP not in SPF record")
    }

    @Test("Preserves multiple Authentication-Results headers from different servers separately")
    func preservesMultipleHeaders() throws {
        let raw = "Authentication-Results: mx.ourcompany.com; spf=fail smtp.mailfrom=a@evil.example\r\n" +
            "Authentication-Results: relay.someisp.net; spf=pass smtp.mailfrom=a@evil.example\r\n\r\n"
        let message = try makeTestMessage(raw)
        let headers = AuthenticationResultsParser.parseAll(from: message.parsed)
        #expect(headers.count == 2)
        #expect(headers[0].authServID == "mx.ourcompany.com")
        #expect(headers[0].results[0].result == "fail")
        #expect(headers[1].authServID == "relay.someisp.net")
        #expect(headers[1].results[0].result == "pass")
    }

    @Test("Handles a bare 'none' resinfo without crashing")
    func handlesBareNone() throws {
        let raw = "Authentication-Results: mx.example.com; none\r\n\r\n"
        let message = try makeTestMessage(raw)
        let header = AuthenticationResultsParser.parseAll(from: message.parsed)[0]
        #expect(header.results.isEmpty)
    }
}

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

@Suite("AuthenticationAnalyzer")
struct AuthenticationAnalyzerTests {
    @Test("A trusted server reporting SPF, DKIM, and DMARC pass yields Pass verdicts and strict alignment")
    func trustedPassEverything() throws {
        let raw = "From: billing@example.com\r\n" +
            "Authentication-Results: mx.ourcompany.com; spf=pass smtp.mailfrom=billing@example.com; dkim=pass header.d=example.com; dmarc=pass header.from=example.com\r\n\r\n"
        let message = try makeTestMessage(raw)
        let analysis = AuthenticationAnalyzer.analyze(message: message, trustedAuthServIDs: ["mx.ourcompany.com"])
        #expect(analysis.spf.verdict == .pass)
        #expect(analysis.dkim.verdict == .pass)
        #expect(analysis.dmarc.verdict == .pass)
        #expect(analysis.alignment.spfAlignment == .strict)
        #expect(analysis.alignment.dkimAlignment == .strict)
    }

    @Test("DMARC can fail despite SPF and DKIM individually passing, when neither aligns with the From domain")
    func dmarcFailsDespiteIndividualPasses() throws {
        let raw = "From: billing@example.com\r\n" +
            "Authentication-Results: mx.ourcompany.com;" +
            " spf=pass smtp.mailfrom=bounce@bounce.example.net;" +
            " dkim=pass header.d=mail-vendor.example.net;" +
            " dmarc=fail header.from=example.com\r\n\r\n"
        let message = try makeTestMessage(raw)
        let analysis = AuthenticationAnalyzer.analyze(message: message, trustedAuthServIDs: ["mx.ourcompany.com"])
        #expect(analysis.spf.verdict == .pass)
        #expect(analysis.dkim.verdict == .pass)
        #expect(analysis.dmarc.verdict == .fail)
        #expect(analysis.alignment.spfAlignment == .notAligned)
        #expect(analysis.alignment.dkimAlignment == .notAligned)
    }

    @Test("A forged Authentication-Results header from an untrusted server never produces a trusted Pass")
    func forgedHeaderFromUntrustedServerIsNotTrusted() throws {
        let raw = "From: victim@example.com\r\n" +
            "Authentication-Results: attacker-mx.evil.example; spf=pass dkim=pass dmarc=pass\r\n\r\n"
        let message = try makeTestMessage(raw)
        // No trusted servers configured at all.
        let analysis = AuthenticationAnalyzer.analyze(message: message, trustedAuthServIDs: ["mx.ourcompany.com"])
        #expect(analysis.spf.verdict == .unknown)
        #expect(analysis.dkim.verdict == .unknown)
        #expect(analysis.dmarc.verdict == .unknown)
        #expect(analysis.spf.trustedResults.isEmpty)
        #expect(analysis.spf.unverifiedResults.count == 1)
        #expect(analysis.spf.unverifiedResults[0].authServID == "attacker-mx.evil.example")
    }

    @Test("Multiple Authentication-Results headers from different servers: only the trusted one drives the verdict")
    func onlyTrustedServerDrivesVerdict() throws {
        let raw = "From: a@example.com\r\n" +
            "Authentication-Results: mx.ourcompany.com; spf=fail smtp.mailfrom=a@evil.example\r\n" +
            "Authentication-Results: relay.someisp.net; spf=pass smtp.mailfrom=a@evil.example\r\n\r\n"
        let message = try makeTestMessage(raw)
        let analysis = AuthenticationAnalyzer.analyze(message: message, trustedAuthServIDs: ["mx.ourcompany.com"])
        #expect(analysis.spf.verdict == .fail)
        #expect(analysis.spf.trustedResults.count == 1)
        #expect(analysis.spf.unverifiedResults.count == 1)
    }

    @Test("A message with no Authentication-Results headers reports Unknown for every method")
    func missingAuthenticationInfoIsUnknown() throws {
        let message = try makeTestMessage("From: a@example.com\r\n\r\n")
        let analysis = AuthenticationAnalyzer.analyze(message: message, trustedAuthServIDs: ["mx.ourcompany.com"])
        #expect(analysis.spf.verdict == .unknown)
        #expect(analysis.dkim.verdict == .unknown)
        #expect(analysis.dmarc.verdict == .unknown)
        #expect(analysis.authenticationResultsHeaders.isEmpty)
    }
}

@Suite("DomainAlignment")
struct DomainAlignmentTests {
    @Test("Identical domains are strictly aligned")
    func exactMatch() {
        #expect(DomainAlignment.align("example.com", "example.com") == .strict)
    }

    @Test("A subdomain is relaxed-aligned with its parent organizational domain")
    func subdomainIsRelaxedAligned() {
        #expect(DomainAlignment.align("mail.example.com", "example.com") == .relaxed)
    }

    @Test("Unrelated domains are not aligned")
    func unrelatedDomainsAreNotAligned() {
        #expect(DomainAlignment.align("example.com", "evil.example") == .notAligned)
    }

    @Test("Recognizes common multi-label suffixes when computing the organizational domain")
    func multiLabelSuffix() {
        #expect(DomainAlignment.align("mail.example.co.uk", "example.co.uk") == .relaxed)
        #expect(DomainAlignment.align("example.co.uk", "other.co.uk") == .notAligned)
    }

    @Test("Resolves gov.gr/gov.cy-style multi-label government suffixes using the public suffix list, not a two-label guess")
    func governmentMultiLabelSuffixes() {
        #expect(DomainAlignment.align("mail.ministry.gov.gr", "ministry.gov.gr") == .relaxed)
        #expect(DomainAlignment.align("ministry.gov.gr", "otherministry.gov.gr") == .notAligned)
        #expect(DomainAlignment.align("mail.example.gov.cy", "example.gov.cy") == .relaxed)
    }
}

@Suite("PublicSuffixList")
struct PublicSuffixListTests {
    @Test("Computes the organizational domain one label below the longest matching suffix")
    func organizationalDomainUsesLongestMatch() {
        #expect(PublicSuffixList.shared.organizationalDomain(of: "mail.ministry.gov.gr") == "ministry.gov.gr")
        #expect(PublicSuffixList.shared.organizationalDomain(of: "example.com") == "example.com")
        #expect(PublicSuffixList.shared.organizationalDomain(of: "mail.example.com") == "example.com")
    }

    @Test("Falls back to the last label for an unrecognized single-label input")
    func singleLabelDomainReturnsItself() {
        #expect(PublicSuffixList.shared.organizationalDomain(of: "localhost") == "localhost")
    }
}
