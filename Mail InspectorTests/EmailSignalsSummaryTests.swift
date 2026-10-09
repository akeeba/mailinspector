//
//  Mail Inspector
//
//  Copyright (c) 2026 Nicholas K. Dionysopoulos
//  Licensed under the MIT License. See license.txt in the project root for details.
//

import Testing
import Foundation
@testable import Mail_Inspector

/// Tests for `EmailSignalsSummary`: the plain-text digest of already-computed signals
/// (SPF/DKIM/DMARC verdicts, delivery-path flags, sender-identity observations, spam score) that
/// is the only thing ever sent into the on-device model's prompt — never raw headers or body.
@Suite("EmailSignalsSummary")
struct EmailSignalsSummaryTests {
    @Test("Includes subject, SPF/DKIM/DMARC verdicts, hop count, and the spam score")
    func includesCoreSignals() throws {
        let raw = "From: Test Sender <sender@example.com>\r\n" +
            "Subject: Hello\r\n" +
            "Authentication-Results: mx.example.com; spf=pass smtp.mailfrom=sender@example.com; dkim=pass header.d=example.com; dmarc=pass header.from=example.com\r\n" +
            "Received: from mail.example.com (mail.example.com [203.0.113.5]) by mx.recipient.example; Mon, 2 Jan 2006 15:04:05 +0000\r\n" +
            "X-Spam-Score: 1.0\r\n\r\n"
        let message = try makeTestMessage(raw)
        let authentication = AuthenticationAnalyzer.analyze(message: message, trustedAuthServIDs: [], trustAllByDefault: true)
        let deliveryPath = DeliveryPathAnalyzer.analyze(message: message, trustedAuthServIDs: [])
        let spamAssessment = SpamLikelihoodAnalyzer.assess(parsed: message.parsed)

        let summary = EmailSignalsSummary.build(
            message: message,
            authentication: authentication,
            deliveryPath: deliveryPath,
            senderIdentityObservations: [],
            spamAssessment: spamAssessment
        )

        #expect(summary.contains("Subject: Hello"))
        #expect(summary.contains("SPF: pass"))
        #expect(summary.contains("DKIM: pass"))
        #expect(summary.contains("DMARC: pass"))
        #expect(summary.contains("Delivery hops: 1"))
        #expect(summary.contains("Spam filter score: 30%"))
    }

    @Test("Reports the spam score as not available rather than omitting the line entirely")
    func reportsMissingSpamScore() throws {
        let message = try makeTestMessage("From: a@example.com\r\nSubject: Test\r\n\r\n")
        let authentication = AuthenticationAnalyzer.analyze(message: message, trustedAuthServIDs: [], trustAllByDefault: true)
        let deliveryPath = DeliveryPathAnalyzer.analyze(message: message, trustedAuthServIDs: [])

        let summary = EmailSignalsSummary.build(
            message: message,
            authentication: authentication,
            deliveryPath: deliveryPath,
            senderIdentityObservations: [],
            spamAssessment: nil
        )

        #expect(summary.contains("Spam filter score: not available"))
    }

    @Test("Includes a sender-identity observation together with its severity")
    func includesSenderIdentityObservations() throws {
        let message = try makeTestMessage("From: a@example.com\r\nSubject: Test\r\n\r\n")
        let authentication = AuthenticationAnalyzer.analyze(message: message, trustedAuthServIDs: [], trustAllByDefault: true)
        let deliveryPath = DeliveryPathAnalyzer.analyze(message: message, trustedAuthServIDs: [])
        let observation = SecurityObservation(id: 0, severity: .warning, title: "Forged display name", detail: "Something is off.")

        let summary = EmailSignalsSummary.build(
            message: message,
            authentication: authentication,
            deliveryPath: deliveryPath,
            senderIdentityObservations: [observation],
            spamAssessment: nil
        )

        #expect(summary.contains("Forged display name"))
        #expect(summary.contains("[warning]"))
    }

    @Test("Includes a hop's notable/warning flags, naming the offending hop")
    func includesHopFlags() throws {
        let raw = "Received: from totally-different.example (actual-ptr.evil.example [203.0.113.5]) by mx.recipient.example; Mon, 2 Jan 2006 15:04:05 +0000\r\n\r\n"
        let message = try makeTestMessage(raw)
        let authentication = AuthenticationAnalyzer.analyze(message: message, trustedAuthServIDs: [], trustAllByDefault: true)
        let deliveryPath = DeliveryPathAnalyzer.analyze(message: message, trustedAuthServIDs: [])

        let summary = EmailSignalsSummary.build(
            message: message,
            authentication: authentication,
            deliveryPath: deliveryPath,
            senderIdentityObservations: [],
            spamAssessment: nil
        )

        #expect(summary.contains("totally-different.example"))
        #expect(summary.contains("does not match"))
        #expect(summary.contains("[warning]"))
    }
}
