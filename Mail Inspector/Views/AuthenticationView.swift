import SwiftUI

/// Section B: SPF, DKIM, and DMARC, as reported by mail servers.
///
/// Never presents a combined "this message is safe" signal — each badge is scoped to a single
/// method, and even a trusted "Pass" only means a trusted server reported that one check passed.
struct AuthenticationView: View {
    let analysis: AuthenticationAnalysis

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Authentication")
                .font(.headline)

            Text("These results are reported by mail servers, not independently verified by this app. A trusted server's \"Pass\" means that server reported a pass — not that the message is safe.")
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                MethodResultRow(summary: analysis.spf)
                MethodResultRow(summary: analysis.dkim)
                MethodResultRow(summary: analysis.dmarc)
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

private extension AuthenticationVerdict {
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
                .frame(width: 110, alignment: .leading)
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
        }
    }
}
