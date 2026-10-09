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

    @Test("trustAllByDefault treats every authserv-id as trusted without an explicit allowlist")
    func trustAllByDefaultBypassesTheAllowlist() throws {
        let raw = "From: a@example.com\r\n" +
            "Authentication-Results: mx.google.com; spf=pass smtp.mailfrom=a@example.com; dkim=pass header.d=example.com\r\n\r\n"
        let message = try makeTestMessage(raw)
        let analysis = AuthenticationAnalyzer.analyze(message: message, trustedAuthServIDs: [], trustAllByDefault: true)
        #expect(analysis.spf.verdict == .pass)
        #expect(analysis.spf.trustedResults.count == 1)
        #expect(analysis.spf.unverifiedResults.isEmpty)
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

@Suite("ReceivedHeaderParser")
struct ReceivedHeaderParserTests {
    @Test("Parses hostname, IP, receiving host, protocol, TLS info, and timestamp from a well-formed hop")
    func parsesWellFormedHop() throws {
        let raw = "Received: from mail.sender.example (mail.sender.example [192.0.2.10])\r\n" +
            " by mx.recipient.example with ESMTPS id ABC123\r\n" +
            " (version=TLS1.3 cipher=AEAD-AES256-GCM-SHA384 bits=256/256)\r\n" +
            " for <bob@recipient.example>; Mon, 2 Jan 2006 15:04:05 +0000\r\n\r\n"
        let message = try makeTestMessage(raw)
        let hop = ReceivedHeaderParser.parseAll(from: message.parsed)[0]
        #expect(hop.claimedFromHostname == "mail.sender.example")
        #expect(hop.verifiedFromHostname == "mail.sender.example")
        #expect(hop.fromIPAddress == "192.0.2.10")
        #expect(hop.byHostname == "mx.recipient.example")
        #expect(hop.withProtocol?.hasPrefix("ESMTPS") == true)
        #expect(hop.tlsVersion == "TLS1.3")
        #expect(hop.tlsCipher == "AEAD-AES256-GCM-SHA384")
        #expect(hop.timestamp != nil)
        #expect(hop.parseWarnings.isEmpty)
    }

    @Test("Surfaces a claimed hostname that differs from the receiver-verified (reverse DNS) hostname")
    func claimedAndVerifiedHostnamesCanDiffer() throws {
        let raw = "Received: from totally-different.example (actual-ptr.evil.example [203.0.113.5]) by mx.recipient.example; Mon, 2 Jan 2006 15:04:05 +0000\r\n\r\n"
        let message = try makeTestMessage(raw)
        let hop = ReceivedHeaderParser.parseAll(from: message.parsed)[0]
        #expect(hop.claimedFromHostname == "totally-different.example")
        #expect(hop.verifiedFromHostname == "actual-ptr.evil.example")
    }

    @Test("Parses a bracketed IP literal with no parenthetical remark")
    func bracketedIPWithoutParenthetical() throws {
        let raw = "Received: from [10.0.0.5] by mx.recipient.example; Mon, 2 Jan 2006 15:04:05 +0000\r\n\r\n"
        let message = try makeTestMessage(raw)
        let hop = ReceivedHeaderParser.parseAll(from: message.parsed)[0]
        #expect(hop.fromIPAddress == "10.0.0.5")
    }

    @Test("Strips the IPv6: prefix from a bracketed IPv6 address")
    func ipv6BracketedAddress() throws {
        let raw = "Received: from host.example (host.example [IPv6:2001:db8::1]) by mx.recipient.example; Mon, 2 Jan 2006 15:04:05 +0000\r\n\r\n"
        let message = try makeTestMessage(raw)
        let hop = ReceivedHeaderParser.parseAll(from: message.parsed)[0]
        #expect(hop.fromIPAddress == "2001:db8::1")
    }

    @Test("Records 'unknown' as the verified hostname when reverse DNS failed")
    func unknownReverseDNS() throws {
        let raw = "Received: from mail.example.com (unknown [198.51.100.7]) by mx.recipient.example; Mon, 2 Jan 2006 15:04:05 +0000\r\n\r\n"
        let message = try makeTestMessage(raw)
        let hop = ReceivedHeaderParser.parseAll(from: message.parsed)[0]
        #expect(hop.verifiedFromHostname == "unknown")
    }

    @Test("Flags a missing 'from' clause instead of silently ignoring the malformed header")
    func missingFromClause() throws {
        let raw = "Received: by mx.recipient.example; Mon, 2 Jan 2006 15:04:05 +0000\r\n\r\n"
        let message = try makeTestMessage(raw)
        let hop = ReceivedHeaderParser.parseAll(from: message.parsed)[0]
        #expect(hop.claimedFromHostname == nil)
        #expect(hop.parseWarnings.contains { $0.contains("from") })
    }

    @Test("Flags an unparseable timestamp instead of silently ignoring it")
    func malformedTimestamp() throws {
        let raw = "Received: from a.example by b.example; not-a-date\r\n\r\n"
        let message = try makeTestMessage(raw)
        let hop = ReceivedHeaderParser.parseAll(from: message.parsed)[0]
        #expect(hop.timestamp == nil)
        #expect(hop.parseWarnings.contains { $0.contains("timestamp") })
    }

    @Test("Does not merge an unrelated second parenthetical (e.g. a TLS-info remark) into the reverse-DNS hostname")
    func secondUnrelatedParentheticalIsNotMergedIntoVerifiedHostname() throws {
        let raw = "Received: from mx2.mailbox.org ([2001:67c:2050:104:0:2:25:2])\r\n" +
            "    (using TLSv1.3 with cipher TLS_AES_256_GCM_SHA384 (256/256 bits))\r\n" +
            "    by director-20.heinlein-hosting.de with LMTPS\r\n" +
            "    id yLUPJ3mux2p02wAACwj3lQ\r\n" +
            "    (envelope-from <Hs-no.reply@e-prescription.gr>)\r\n" +
            "    for <nicholas@dionysopoulos.me>; Thu, 08 Oct 2026 16:53:45 +0200\r\n\r\n"
        let message = try makeTestMessage(raw)
        let hop = ReceivedHeaderParser.parseAll(from: message.parsed)[0]
        #expect(hop.claimedFromHostname == "mx2.mailbox.org")
        #expect(hop.fromIPAddress == "2001:67c:2050:104:0:2:25:2")
        #expect(hop.verifiedFromHostname == nil)
        #expect(hop.byHostname == "director-20.heinlein-hosting.de")
        #expect(hop.tlsVersion == "TLSv1.3")
        #expect(hop.tlsCipher == "TLS_AES_256_GCM_SHA384")
    }
}

@Suite("IPAddressClassifier")
struct IPAddressClassifierTests {
    @Test("Classifies common IPv4 scopes")
    func ipv4Scopes() {
        #expect(IPAddressClassifier.classify("192.168.1.1") == .privateUse)
        #expect(IPAddressClassifier.classify("10.0.0.1") == .privateUse)
        #expect(IPAddressClassifier.classify("172.16.0.1") == .privateUse)
        #expect(IPAddressClassifier.classify("127.0.0.1") == .loopback)
        #expect(IPAddressClassifier.classify("169.254.1.1") == .linkLocal)
        #expect(IPAddressClassifier.classify("100.64.0.1") == .carrierGradeNAT)
        #expect(IPAddressClassifier.classify("8.8.8.8") == .publicAddress)
    }

    @Test("Classifies common IPv6 scopes")
    func ipv6Scopes() {
        #expect(IPAddressClassifier.classify("::1") == .loopback)
        #expect(IPAddressClassifier.classify("fe80::1") == .linkLocal)
        #expect(IPAddressClassifier.classify("fd00::1") == .uniqueLocal)
        #expect(IPAddressClassifier.classify("2001:db8::1") == .documentationOrReserved)
        #expect(IPAddressClassifier.classify("2607:f8b0::1") == .publicAddress)
    }

    @Test("Returns nil for text that isn't a valid IP address")
    func invalidAddress() {
        #expect(IPAddressClassifier.classify("not-an-ip") == nil)
    }
}

@Suite("DeliveryPathAnalyzer")
struct DeliveryPathAnalyzerTests {
    @Test("Orders hops oldest to newest, reversing the header's newest-first order")
    func ordersHopsOldestToNewest() throws {
        let raw = "Received: from hop3.example by final.example; Wed, 4 Jan 2006 10:00:00 +0000\r\n" +
            "Received: from hop2.example by hop3.example; Tue, 3 Jan 2006 10:00:00 +0000\r\n" +
            "Received: from hop1.example by hop2.example; Mon, 2 Jan 2006 10:00:00 +0000\r\n\r\n"
        let message = try makeTestMessage(raw)
        let analysis = DeliveryPathAnalyzer.analyze(message: message, trustedAuthServIDs: [])
        #expect(analysis.hops.count == 3)
        #expect(analysis.hops[0].claimedFromHostname == "hop1.example")
        #expect(analysis.hops[1].claimedFromHostname == "hop2.example")
        #expect(analysis.hops[2].claimedFromHostname == "hop3.example")
    }

    @Test("Flags a hop whose timestamp is earlier than the previous hop's as chronologically inconsistent")
    func flagsChronologicalInconsistency() throws {
        let raw = "Received: from newer.example by final.example; Mon, 2 Jan 2006 00:00:00 +0000\r\n" +
            "Received: from older.example by newer.example; Wed, 4 Jan 2006 00:00:00 +0000\r\n\r\n"
        let message = try makeTestMessage(raw)
        let analysis = DeliveryPathAnalyzer.analyze(message: message, trustedAuthServIDs: [])
        #expect(analysis.hops[1].warnings.contains { $0.contains("chronologically inconsistent") })
    }

    @Test("Flags an unusually long transit delay between consecutive hops")
    func flagsLongTransitDelay() throws {
        let raw = "Received: from newer.example by final.example; Wed, 4 Jan 2006 00:00:00 +0000\r\n" +
            "Received: from older.example by newer.example; Mon, 2 Jan 2006 00:00:00 +0000\r\n\r\n"
        let message = try makeTestMessage(raw)
        let analysis = DeliveryPathAnalyzer.analyze(message: message, trustedAuthServIDs: [])
        #expect(analysis.hops[1].warnings.contains { $0.contains("unusually long") })
    }

    @Test("Does not flag a leading run of private-use hops, since that's how most SaaS senders normally relay internally before reaching the public internet")
    func doesNotFlagLeadingInternalHops() throws {
        let raw = "Received: from edge.example (edge.example [203.0.113.9]) by mx.example; Mon, 2 Jan 2006 00:02:00 +0000\r\n" +
            "Received: from aggregator.internal (aggregator.internal [10.0.0.6]) by edge.example; Mon, 2 Jan 2006 00:01:00 +0000\r\n" +
            "Received: from appserver.internal (appserver.internal [10.0.0.5]) by aggregator.internal; Mon, 2 Jan 2006 00:00:00 +0000\r\n\r\n"
        let message = try makeTestMessage(raw)
        let analysis = DeliveryPathAnalyzer.analyze(message: message, trustedAuthServIDs: [])
        #expect(analysis.hops[0].fromIPScope == .privateUse)
        #expect(analysis.hops[1].fromIPScope == .privateUse)
        #expect(analysis.hops[0].warnings.isEmpty)
        #expect(analysis.hops[1].warnings.isEmpty)
    }

    @Test("Flags a private-use sending IP address that appears after the message already reached the public internet")
    func flagsPrivateIPAfterPublicHop() throws {
        // 8.8.8.8 and 1.1.1.1 are genuinely public IPs (unlike the RFC 5737 documentation/
        // test-net ranges, which this app's own classifier correctly treats as non-public).
        let raw = "Received: from mx.example (mx.example [8.8.8.8]) by final.example; Mon, 2 Jan 2006 00:02:00 +0000\r\n" +
            "Received: from suspicious.internal (suspicious.internal [10.0.0.5]) by mx.example; Mon, 2 Jan 2006 00:01:00 +0000\r\n" +
            "Received: from first.example (first.example [1.1.1.1]) by suspicious.internal; Mon, 2 Jan 2006 00:00:00 +0000\r\n\r\n"
        let message = try makeTestMessage(raw)
        let analysis = DeliveryPathAnalyzer.analyze(message: message, trustedAuthServIDs: [])
        #expect(analysis.hops[1].fromIPScope == .privateUse)
        #expect(analysis.hops[1].warnings.contains { $0.contains("private-use") })
    }

    @Test("Marks only the trusted suffix of hops as trusted, stopping at the first non-matching hop")
    func marksTrustBoundary() throws {
        let raw = "Received: from upstream.example by mx.ourcompany.com; Wed, 4 Jan 2006 00:00:00 +0000\r\n" +
            "Received: from sender.example by relay.someisp.net; Mon, 2 Jan 2006 00:00:00 +0000\r\n\r\n"
        let message = try makeTestMessage(raw)
        let analysis = DeliveryPathAnalyzer.analyze(message: message, trustedAuthServIDs: ["mx.ourcompany.com"])
        #expect(analysis.hops[0].isTrusted == false)
        #expect(analysis.hops[1].isTrusted == true)
    }

    @Test("Leaves trust undeterminable (nil), not false, when no trusted servers are configured")
    func trustIsUndeterminableWithoutConfiguration() throws {
        let raw = "Received: from sender.example by mx.example; Mon, 2 Jan 2006 00:00:00 +0000\r\n\r\n"
        let message = try makeTestMessage(raw)
        let analysis = DeliveryPathAnalyzer.analyze(message: message, trustedAuthServIDs: [])
        #expect(analysis.hops[0].isTrusted == nil)
    }

    @Test("Reports no delivery path rather than crashing when there are no Received headers")
    func noReceivedHeaders() throws {
        let message = try makeTestMessage("From: a@b.com\r\n\r\n")
        let analysis = DeliveryPathAnalyzer.analyze(message: message, trustedAuthServIDs: [])
        #expect(analysis.hops.isEmpty)
        #expect(analysis.observations.contains { $0.title == "No delivery path" })
    }
}

@Suite("SenderIdentityAnalyzer")
struct SenderIdentityAnalyzerTests {
    @Test("Flags a display name containing an address that differs from the actual From address")
    func forgedDisplayName() throws {
        let message = try makeTestMessage("From: \"support@bank.example\" <attacker@evil.example>\r\n\r\n")
        let analysis = SenderIdentityAnalyzer.analyze(message: message)
        #expect(analysis.observations.contains { $0.title == "Display name contains a different address" })
    }

    @Test("Flags multiple From headers")
    func multipleFromHeaders() throws {
        let message = try makeTestMessage("From: a@b.com\r\nFrom: c@d.com\r\n\r\n")
        let analysis = SenderIdentityAnalyzer.analyze(message: message)
        #expect(analysis.observations.contains { $0.title == "Multiple From headers" })
    }

    @Test("Flags a Reply-To domain that is not organizationally related to the From domain")
    func replyToMismatch() throws {
        let message = try makeTestMessage("From: billing@bank.example\r\nReply-To: attacker@evil.example\r\n\r\n")
        let analysis = SenderIdentityAnalyzer.analyze(message: message)
        #expect(analysis.observations.contains { $0.title == "Reply-To domain differs from From" })
    }

    @Test("Flags a Return-Path domain that is not organizationally related to the From domain, at informational severity")
    func returnPathMismatch() throws {
        let message = try makeTestMessage("From: billing@bank.example\r\nReturn-Path: <bounce@othermailer.example>\r\n\r\n")
        let analysis = SenderIdentityAnalyzer.analyze(message: message)
        let observation = analysis.observations.first { $0.title == "Return-Path domain differs from From" }
        #expect(observation != nil)
        #expect(observation?.severity == .info)
    }

    @Test("Flags a Punycode (IDN) From domain as informational, not as proof of impersonation")
    func idnDomain() throws {
        let message = try makeTestMessage("From: user@xn--mnich-kva.example\r\n\r\n")
        let analysis = SenderIdentityAnalyzer.analyze(message: message)
        let observation = analysis.observations.first { $0.title == "Internationalized domain name" }
        #expect(observation != nil)
        #expect(observation?.severity == .info)
    }

    @Test("Flags a display name mixing Latin and Cyrillic characters")
    func mixedScriptDisplayName() throws {
        // "Support" with a Cyrillic 'а' (U+0430) replacing the Latin 'a'.
        let message = try makeTestMessage("From: \"Supp\u{0430}rt\" <support@example.com>\r\n\r\n")
        let analysis = SenderIdentityAnalyzer.analyze(message: message)
        #expect(analysis.observations.contains { $0.title == "Mixed-script characters in display name" })
    }

    @Test("A clean message with no discrepancies produces no observations")
    func cleanMessageHasNoObservations() throws {
        let message = try makeTestMessage("From: \"Alice\" <alice@example.com>\r\nReply-To: alice@example.com\r\n\r\n")
        let analysis = SenderIdentityAnalyzer.analyze(message: message)
        #expect(analysis.observations.isEmpty)
    }
}

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

@Suite("SpamLikelihoodAnalyzer")
struct SpamLikelihoodAnalyzerTests {
    @Test("Rescales an X-Spam-Score onto a 0-100 gauge")
    func rescalesSpamScore() throws {
        let message = try makeTestMessage("X-Spam-Score: 5.0\r\n\r\n")
        let assessment = SpamLikelihoodAnalyzer.assess(parsed: message.parsed)
        #expect(assessment?.sourceHeaderName == "X-Spam-Score")
        #expect(assessment?.percentage == 50)
    }

    @Test("Extracts the score from an X-Spam-Status line when X-Spam-Score is absent")
    func extractsScoreFromStatusLine() throws {
        let message = try makeTestMessage("X-Spam-Status: No, score=-2.3 required=5.0 tests=NONE\r\n\r\n")
        let assessment = SpamLikelihoodAnalyzer.assess(parsed: message.parsed)
        #expect(assessment?.sourceHeaderName == "X-Spam-Status")
        #expect(assessment?.percentage == 13.5)
    }

    @Test("Rescales Exchange's Spam Confidence Level onto a 0-100 gauge")
    func rescalesSCL() throws {
        let message = try makeTestMessage("X-MS-Exchange-Organization-SCL: 9\r\n\r\n")
        let assessment = SpamLikelihoodAnalyzer.assess(parsed: message.parsed)
        #expect(assessment?.sourceHeaderName == "X-MS-Exchange-Organization-SCL")
        #expect(assessment?.percentage == 100)
    }

    @Test("Rescales an Rspamd score relative to its own required-score threshold")
    func rescalesRspamdScore() throws {
        let message = try makeTestMessage("X-Rspamd-Score: -9.58 / 15.00 / 15.00\r\n\r\n")
        let assessment = SpamLikelihoodAnalyzer.assess(parsed: message.parsed)
        #expect(assessment?.sourceHeaderName == "X-Rspamd-Score")
        #expect(assessment?.percentage == 0) // clamped: -9.58/15*50 is negative
    }

    @Test("Skips a blank X-MBO-SPAM-Probability header instead of crashing, falling through to the next source")
    func skipsBlankMBOHeader() throws {
        let message = try makeTestMessage("X-MBO-SPAM-Probability: \r\nX-Rspamd-Score: 20 / 15.00\r\n\r\n")
        let assessment = SpamLikelihoodAnalyzer.assess(parsed: message.parsed)
        #expect(assessment?.sourceHeaderName == "X-Rspamd-Score")
    }

    @Test("Interprets a fractional X-MBO-SPAM-Probability as 0-1, rescaled to a percentage")
    func interpretsMBOFraction() throws {
        let message = try makeTestMessage("X-MBO-SPAM-Probability: 0.75\r\n\r\n")
        let assessment = SpamLikelihoodAnalyzer.assess(parsed: message.parsed)
        #expect(assessment?.sourceHeaderName == "X-MBO-SPAM-Probability")
        #expect(assessment?.percentage == 75)
    }

    @Test("Returns nil when no recognized spam-scoring header is present")
    func returnsNilWithoutRecognizedHeader() throws {
        let message = try makeTestMessage("From: a@b.com\r\n\r\n")
        #expect(SpamLikelihoodAnalyzer.assess(parsed: message.parsed) == nil)
    }
}

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

@Suite("SPFRecheckTargetResolver")
struct SPFRecheckTargetResolverTests {
    @Test("Prefers a Received-SPF header when one is present with both fields")
    func prefersReceivedSPF() throws {
        let raw = "From: a@epafos.gr\r\n" +
            "Received-SPF: pass client-ip=51.145.238.12; envelope-from=4schools-info@epafos.gr;\r\n" +
            "Authentication-Results: mx.google.com; spf=pass smtp.mailfrom=other@other.example smtp.client-ip=9.9.9.9\r\n\r\n"
        let message = try makeTestMessage(raw)
        let authentication = AuthenticationAnalyzer.analyze(message: message, trustedAuthServIDs: [], trustAllByDefault: true)
        let target = SPFRecheckTargetResolver.resolve(message: message, authentication: authentication)
        #expect(target?.source == "Received-SPF")
        #expect(target?.ip == "51.145.238.12")
        #expect(target?.domain == "epafos.gr")
    }

    @Test("Falls back to Authentication-Results smtp.mailfrom/smtp.client-ip when there's no Received-SPF header")
    func fallsBackToAuthenticationResults() throws {
        let raw = "From: a@example.com\r\n" +
            "Authentication-Results: mx.google.com; spf=pass smtp.mailfrom=sender@example.com smtp.client-ip=9.9.9.9\r\n\r\n"
        let message = try makeTestMessage(raw)
        let authentication = AuthenticationAnalyzer.analyze(message: message, trustedAuthServIDs: [], trustAllByDefault: true)
        let target = SPFRecheckTargetResolver.resolve(message: message, authentication: authentication)
        #expect(target?.ip == "9.9.9.9")
        #expect(target?.domain == "example.com")
    }

    @Test("Returns nil when neither source has enough information")
    func returnsNilWithoutEnoughInformation() throws {
        let message = try makeTestMessage("From: a@example.com\r\n\r\n")
        let authentication = AuthenticationAnalyzer.analyze(message: message, trustedAuthServIDs: [], trustAllByDefault: true)
        #expect(SPFRecheckTargetResolver.resolve(message: message, authentication: authentication) == nil)
    }
}
