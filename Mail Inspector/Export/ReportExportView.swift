//
//  Mail Inspector
//
//  Copyright (c) 2026 Nicholas K. Dionysopoulos
//  Licensed under the MIT License. See license.txt in the project root for details.
//

import SwiftUI

/// The Apple Intelligence score and prose analysis for one message, already generated while it
/// was open in the detail view — plain, always-available types only, since `MessageInsightsSession`
/// itself requires macOS 27 and this needs to flow through export code that doesn't. The chat
/// transcript is deliberately excluded: it's a conversation, not a fact to report.
struct AIInsightsExportSummary {
    let score: Int
    let rationale: String
    let analysisText: String
}

/// A static, non-interactive rendering of a message's full analysis, built specifically for
/// PDF export/sharing (via `ReportPDFExporter`) rather than on-screen reading. Unlike
/// `MessageDetailView`, nothing here is collapsed, searchable, or clickable — a PDF has no
/// disclosure state and no "Recheck SPF Now" button to press, so every section is always fully
/// expanded and includes only what's meaningful on paper: headers, signals, recipient, and the
/// Message-ID an IT department would need to locate the message on their own mail servers.
///
/// `blocks` exposes the report as a flat, ordered list of atomic, never-split units rather than
/// one big view — `ReportPDFExporter` measures and paginates at this granularity (one delivery
/// hop, one raw header field, one observation, etc.) so a single line can never be cut in half
/// across a page boundary the way it would be with a naive clip-and-slice approach.
struct ReportExportView: View {
    /// Shared with `ReportPDFExporter`, which re-assembles subsets of `blocks` into per-page
    /// `VStack`s and needs to reproduce this exact spacing for its height measurements to match
    /// what actually gets drawn.
    static let blockSpacing: CGFloat = 20

    let message: EmailMessage
    let settings: InspectorSettings
    var aiInsights: AIInsightsExportSummary? = nil

    private var senderIdentityAnalysis: SenderIdentityAnalysis {
        SenderIdentityAnalyzer.analyze(message: message, trustedReplyToDomainsByRecipient: settings.trustedReplyToDomainsByRecipient)
    }

    private var authenticationAnalysis: AuthenticationAnalysis {
        AuthenticationAnalyzer.analyze(
            message: message,
            trustedAuthServIDs: settings.trustedAuthServIDs,
            trustAllByDefault: settings.trustAllAuthenticationResultsByDefault
        )
    }

    private var deliveryPathAnalysis: DeliveryPathAnalysis {
        DeliveryPathAnalyzer.analyze(message: message, trustedAuthServIDs: settings.trustedAuthServIDs, trustedHostnameMismatches: settings.trustedHostnameMismatches)
    }

    private var additionalHeaders: [AdditionalSecurityHeader] {
        SecurityHeaderCatalog.presentHeaders(in: message.parsed)
    }

    private var spamAssessment: SpamLikelihoodAssessment? {
        guard settings.trustServerSpamHeaders else { return nil }
        return SpamLikelihoodAnalyzer.assess(parsed: message.parsed)
    }

    /// Always included in the exported report regardless of the in-app "Show Noteworthy
    /// Observations" setting — that toggle exists to reduce on-screen noise while reading, not
    /// to suppress signal data from a report meant for someone else to act on.
    private var combinedObservations: [SecurityObservation] {
        (senderIdentityAnalysis.observations + deliveryPathAnalysis.observations)
            .enumerated()
            .map { index, observation in
                SecurityObservation(id: index, severity: observation.severity, title: observation.title, detail: observation.detail)
            }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Self.blockSpacing) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in block }
        }
        .padding(36)
        .foregroundStyle(.black)
        .background(Color.white)
    }

    /// Every atomic unit of the report, in display order. See the type-level documentation for
    /// why this exists as a flat list rather than nested section views.
    var blocks: [AnyView] {
        var items: [AnyView] = [AnyView(header)]

        items.append(AnyView(sectionHeading("Message Identification")))
        items.append(AnyView(messageIdentificationTable))

        items.append(AnyView(sectionHeading("Authentication Signals")))
        items.append(AnyView(methodBlock("SPF", authenticationAnalysis.spf)))
        items.append(AnyView(methodBlock("DKIM", authenticationAnalysis.dkim)))
        items.append(AnyView(methodBlock("DMARC", authenticationAnalysis.dmarc)))
        if authenticationAnalysis.alignment.fromDomain != nil {
            items.append(AnyView(alignmentBlock))
        }

        items.append(AnyView(sectionHeading("Delivery Path")))
        if deliveryPathAnalysis.hops.isEmpty {
            items.append(AnyView(staticLine("This message has no Received headers, so its delivery path cannot be reconstructed.")))
        } else {
            items.append(contentsOf: deliveryPathAnalysis.hops.map { AnyView(hopBlock($0)) })
        }

        if let spamAssessment {
            items.append(AnyView(sectionHeading("Spam Likelihood")))
            items.append(AnyView(spamBlock(spamAssessment)))
        }

        if let aiInsights {
            items.append(AnyView(sectionHeading("Apple Intelligence Analysis (AI-generated — verify independently)")))
            items.append(AnyView(aiInsightsBlock(aiInsights)))
        }

        if !combinedObservations.isEmpty {
            items.append(AnyView(sectionHeading("Noteworthy Observations")))
            items.append(contentsOf: combinedObservations
                .sorted(by: { $0.severity > $1.severity })
                .map { AnyView(observationBlock($0)) })
        }

        if !additionalHeaders.isEmpty {
            items.append(AnyView(sectionHeading("Additional Filtering Headers")))
            items.append(contentsOf: additionalHeaders.map { AnyView(additionalHeaderBlock($0)) })
        }

        items.append(AnyView(sectionHeading("Raw Headers")))
        items.append(contentsOf: message.parsed.headers.map { AnyView(rawHeaderBlock($0)) })

        return items
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Mail Inspector Report")
                .font(.system(size: 22, weight: .bold))
            Text("Generated \(Date().formatted(date: .abbreviated, time: .standard))")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(message.subject ?? "(No Subject)")
                .font(.title3.weight(.semibold))
                .padding(.top, 8)
        }
    }

    private func sectionHeading(_ title: String) -> some View {
        Text(title).font(.headline)
    }

    private var messageIdentificationTable: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 6) {
            if let from = message.primaryFrom {
                staticRow("From", from.displayName.map { "\($0) <\(from.address)>" } ?? from.address)
            }
            if let sender = message.senderAddress {
                staticRow("Sender", sender.address)
            }
            if !message.replyToEntries.isEmpty {
                staticRow("Reply-To", addressSummary(message.replyToEntries))
            }
            if let returnPath = message.returnPath {
                staticRow("Return-Path", returnPath)
            }
            if !message.toEntries.isEmpty {
                staticRow("To (Recipient)", addressSummary(message.toEntries))
            }
            if !message.ccEntries.isEmpty {
                staticRow("Cc", addressSummary(message.ccEntries))
            }
            if let messageID = message.messageID {
                staticRow("Message-ID", messageID)
            }
            if let date = message.date {
                staticRow("Date", date.formatted(date: .abbreviated, time: .standard))
            } else if let raw = message.dateHeaderRaw {
                staticRow("Date (unparsed)", raw)
            }
        }
    }

    @ViewBuilder
    private func methodBlock(_ label: String, _ summary: MethodAuthenticationSummary) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label).font(.subheadline.weight(.semibold))
                Text(summary.verdict.displayLabel)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(summary.verdict.tintColor)
            }
            ForEach(summary.trustedResults) { attributed in
                staticLine("Trusted report from \(attributed.authServID): \(attributed.result.result)\(attributed.result.reason.map { " (\($0))" } ?? "")")
            }
            ForEach(summary.unverifiedResults) { attributed in
                staticLine("Unverified report from \(attributed.authServID): \(attributed.result.result)")
            }
            if summary.attributedResults.isEmpty {
                staticLine("No Authentication-Results header reported this method.")
            }
        }
    }

    private var alignmentBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Domain Alignment").font(.subheadline.weight(.semibold))
            if let spfDomain = authenticationAnalysis.alignment.spfCheckedDomain {
                staticLine("SPF checked domain: \(spfDomain) — \(alignmentLabel(authenticationAnalysis.alignment.spfAlignment))")
            }
            if let dkimDomain = authenticationAnalysis.alignment.dkimSigningDomain {
                staticLine("DKIM signing domain: \(dkimDomain) — \(alignmentLabel(authenticationAnalysis.alignment.dkimAlignment))")
            }
        }
    }

    private func hopBlock(_ hop: DeliveryHop) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Hop \(hop.id + 1): \(hop.claimedFromHostname ?? hop.fromIPAddress ?? "Unknown sender")")
                .font(.subheadline.weight(.semibold))
            if let ip = hop.fromIPAddress {
                staticLine("Sending IP: \(ip)")
            }
            if let by = hop.byHostname {
                staticLine("Received by: \(by)")
            }
            if let timestamp = hop.timestamp {
                staticLine("Timestamp: \(timestamp.formatted(date: .abbreviated, time: .standard))")
            }
            ForEach(hop.flags) { flag in
                Text("\(flagMarker(for: flag.severity)) \(flag.message)")
                    .font(.caption)
                    .foregroundStyle(flag.severity.tintColor)
            }
        }
    }

    /// A plain-text marker standing in for the on-screen SF Symbol, matching this flag's
    /// severity — warnings and notices should read as visually distinct on paper too.
    private func flagMarker(for severity: ObservationSeverity) -> String {
        switch severity {
        case .warning: return "⚠"
        case .notable: return "ℹ"
        case .info: return "•"
        }
    }

    private func spamBlock(_ assessment: SpamLikelihoodAssessment) -> some View {
        staticLine("\(assessment.qualitativeLabel) (\(Int(assessment.percentage.rounded()))%) — as reported by \(assessment.sourceHeaderName) (\(assessment.rawValue)). This reflects the mail provider's own filter, not an independent assessment.")
    }

    private func aiInsightsBlock(_ summary: AIInsightsExportSummary) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Legitimacy score: \(summary.score)%").font(.subheadline.weight(.semibold))
            staticLine(summary.rationale)
            staticLine(summary.analysisText)
            staticLine("Generated on-device by Apple Intelligence from this report's own signals — an AI opinion, not a verdict, and it can be confidently wrong.")
        }
    }

    private func observationBlock(_ observation: SecurityObservation) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(observation.title).font(.subheadline.weight(.semibold))
            staticLine(observation.detail)
        }
    }

    private func additionalHeaderBlock(_ header: AdditionalSecurityHeader) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(header.name).font(.system(.subheadline, design: .monospaced).weight(.semibold))
            staticLine(header.value, monospaced: true)
            Text(header.explanation).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func rawHeaderBlock(_ field: HeaderField) -> some View {
        Text(field.rawText)
            .font(.system(.caption, design: .monospaced))
    }

    @ViewBuilder
    private func staticRow(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
                .gridColumnAlignment(.trailing)
            Text(value)
                .font(.system(.body, design: .monospaced))
        }
    }

    private func staticLine(_ text: String, monospaced: Bool = false) -> some View {
        Text(text)
            .font(monospaced ? .system(.caption, design: .monospaced) : .caption)
            .foregroundStyle(.secondary)
    }

    private func addressSummary(_ entries: [AddressListEntry]) -> String {
        entries.map { entry in
            switch entry {
            case .mailbox(let address):
                return address.address
            case .group(let name, let members):
                return "\(name): \(members.map(\.address).joined(separator: ", "))"
            case .malformed(let raw):
                return "⚠ \(raw)"
            }
        }.joined(separator: ", ")
    }

    private func alignmentLabel(_ result: DomainAlignment.Result?) -> String {
        switch result {
        case .strict: return "Aligned (strict)"
        case .relaxed: return "Aligned (relaxed)"
        case .notAligned: return "Not aligned"
        case nil: return "Not determinable"
        }
    }
}
