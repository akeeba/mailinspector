//
//  Mail Inspector
//
//  Copyright (c) 2026 Nicholas K. Dionysopoulos
//  Licensed under the MIT License. See license.txt in the project root for details.
//

import SwiftUI

/// Section B: SPF, DKIM, and DMARC, as reported by mail servers.
///
/// Never presents a combined "this message is safe" signal — each badge is scoped to a single
/// method, and even a trusted "Pass" only means a trusted server reported that one check passed.
struct AuthenticationView: View {
    let analysis: AuthenticationAnalysis
    let spfRecheckTarget: SPFRecheckTarget?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Authentication")
                .font(.headline)

            Text("These results are reported by mail servers, not independently verified by this app. A trusted server's \"Pass\" means that server reported a pass — not that the message is safe.")
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                MethodResultRow(summary: analysis.spf, spfRecheckTarget: spfRecheckTarget)
                MethodResultRow(summary: analysis.dkim, spfRecheckTarget: nil)
                MethodResultRow(summary: analysis.dmarc, spfRecheckTarget: nil)
            }

            if analysis.alignment.fromDomain != nil {
                AlignmentSummaryView(alignment: analysis.alignment)
            }

            if !analysis.dkimSignatures.isEmpty {
                DKIMSignaturesView(signatures: analysis.dkimSignatures)
            }

            if analysis.authenticationResultsHeaders.isEmpty {
                Text("This message has no Authentication-Results headers.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct VerdictBadge: View {
    let verdict: AuthenticationVerdict

    var body: some View {
        Label(verdict.displayLabel, systemImage: verdict.symbolName)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(verdict.tintColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(verdict.tintColor.opacity(0.15), in: Capsule())
            .accessibilityLabel("\(verdict.displayLabel) status")
    }
}

extension AuthenticationVerdict {
    var displayLabel: String {
        switch self {
        case .pass: return "Pass"
        case .fail: return "Fail"
        case .warning: return "Warning"
        case .unverified: return "Unverified"
        case .unknown: return "Unknown"
        }
    }

    var symbolName: String {
        switch self {
        case .pass: return "checkmark.circle.fill"
        case .fail: return "xmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .unverified: return "questionmark.circle.fill"
        case .unknown: return "circle.dotted"
        }
    }

    var tintColor: Color {
        switch self {
        case .pass: return .green
        case .fail: return .red
        case .warning: return .orange
        case .unverified: return .gray
        case .unknown: return .secondary
        }
    }
}

private struct MethodResultRow: View {
    let summary: MethodAuthenticationSummary
    let spfRecheckTarget: SPFRecheckTarget?
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 10) {
                if summary.trustedResults.isEmpty {
                    Text("No result from a trusted authentication server is available for \(summary.displayName).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(summary.trustedResults) { attributed in
                    AttributedResultRow(attributed: attributed, label: "Trusted report")
                }
                ForEach(summary.unverifiedResults) { attributed in
                    AttributedResultRow(attributed: attributed, label: "Unverified report")
                }
                if let spfRecheckTarget {
                    Divider()
                    SPFRecheckView(target: spfRecheckTarget)
                }
            }
            .padding(.top, 6)
        } label: {
            HStack {
                Text(summary.displayName)
                    .font(.body.weight(.medium))
                Spacer()
                VerdictBadge(verdict: summary.verdict)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.05)))
    }
}

private struct AttributedResultRow: View {
    let attributed: AttributedAuthResult
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(attributed.isTrusted ? Color.secondary : Color.orange)
                Text("· \(attributed.result.result)")
                    .font(.caption.weight(.semibold))
                Spacer()
                Text(attributed.authServID)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            if let reason = attributed.result.reason, !reason.isEmpty {
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !attributed.result.properties.isEmpty {
                Text(attributed.result.properties.map { "\($0.ptype).\($0.property)=\($0.value)" }.joined(separator: "  "))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.06)))
    }
}

private struct AlignmentSummaryView: View {
    let alignment: DMARCAlignmentAnalysis

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Domain Alignment")
                .font(.subheadline.weight(.semibold))
            if let fromDomain = alignment.fromDomain {
                Text("From domain: \(fromDomain)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            row(label: "SPF", domain: alignment.spfCheckedDomain, result: alignment.spfAlignment)
            row(label: "DKIM", domain: alignment.dkimSigningDomain, result: alignment.dkimAlignment)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.05)))
    }

    @ViewBuilder
    private func row(label: String, domain: String?, result: DomainAlignment.Result?) -> some View {
        HStack {
            Text(label).font(.caption.weight(.medium))
            if let domain {
                Text(domain)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            Spacer()
            if let result {
                Text(alignmentLabel(result))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(alignmentColor(result))
            } else {
                Text("Not determinable")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func alignmentLabel(_ result: DomainAlignment.Result) -> String {
        switch result {
        case .strict: return "Aligned (strict)"
        case .relaxed: return "Aligned (relaxed)"
        case .notAligned: return "Not aligned"
        }
    }

    private func alignmentColor(_ result: DomainAlignment.Result) -> Color {
        switch result {
        case .strict, .relaxed: return .green
        case .notAligned: return .orange
        }
    }
}

private struct DKIMSignaturesView: View {
    let signatures: [DKIMSignature]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("DKIM Signatures")
                .font(.subheadline.weight(.semibold))
            ForEach(signatures) { signature in
                DKIMSignatureRow(signature: signature)
            }
        }
    }
}

private struct DKIMSignatureRow: View {
    let signature: DKIMSignature
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 4) {
                if let algorithm = signature.algorithm {
                    detail("Algorithm", algorithm)
                }
                detail("Canonicalization", "\(signature.headerCanonicalization ?? "simple")/\(signature.bodyCanonicalization ?? "simple")")
                if !signature.signedHeaders.isEmpty {
                    detail("Signed Headers", signature.signedHeaders.joined(separator: ", "))
                }
                if let selector = signature.selector {
                    detail("Selector", selector)
                }
                if let identity = signature.identity {
                    detail("Identity", identity)
                }
                if let timestamp = signature.timestamp {
                    detail("Signed", timestamp.formatted(date: .abbreviated, time: .standard))
                }
                if let expiration = signature.expiration {
                    detail("Expires", expiration.formatted(date: .abbreviated, time: .standard))
                }
            }
            .padding(.top, 4)
        } label: {
            Text(signature.signingDomain ?? "(no domain)")
                .font(.system(.body, design: .monospaced))
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.05)))
    }

    @ViewBuilder
    private func detail(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(minWidth: 110, alignment: .leading)
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
        }
    }
}

/// A manual, on-demand SPF recheck against the record as it exists right now — not what was
/// recorded when the message was sent. This is the one place in the app that performs live
/// network verification rather than just parsing reported results, and it only ever runs when
/// explicitly requested by clicking the button.
private struct SPFRecheckView: View {
    let target: SPFRecheckTarget
    @State private var isChecking = false
    @State private var outcome: SPFCheckResult?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Button(action: recheck) {
                    if isChecking {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("Recheck SPF Now")
                    }
                }
                .disabled(isChecking)
                Text("for \(target.ip) against \(target.domain) (from \(target.source))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let outcome {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: symbolName(for: outcome.result))
                        .foregroundStyle(tintColor(for: outcome.result))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(outcome.result.rawValue.capitalized)
                            .font(.caption.weight(.semibold))
                        Text(outcome.explanation)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Text(caveat(for: outcome.result))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func recheck() {
        isChecking = true
        outcome = nil
        Task {
            let result = await SPFEvaluator.evaluate(ip: target.ip, senderDomain: target.domain)
            outcome = result
            isChecking = false
        }
    }

    private func caveat(for result: SPFResult) -> String {
        result == .pass
            ? "This checks the record as it exists right now, not as it was when the message was sent. A pass is a reasonably strong signal the sending IP is currently authorized — but SPF records can change, so this doesn't retroactively prove anything about the past."
            : "This checks the record as it exists right now, not as it was when the message was sent. A non-pass result here proves nothing about the past — the record may have changed since."
    }

    private func symbolName(for result: SPFResult) -> String {
        switch result {
        case .pass: return "checkmark.circle.fill"
        case .fail: return "xmark.circle.fill"
        case .softfail, .neutral, .none: return "exclamationmark.triangle.fill"
        case .temperror, .permerror: return "questionmark.circle.fill"
        }
    }

    private func tintColor(for result: SPFResult) -> Color {
        switch result {
        case .pass: return .green
        case .fail: return .red
        case .softfail, .neutral, .none: return .orange
        case .temperror, .permerror: return .gray
        }
    }
}
