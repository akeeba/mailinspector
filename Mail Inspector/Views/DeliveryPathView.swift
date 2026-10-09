//
//  Mail Inspector
//
//  Copyright (c) 2026 Nicholas K. Dionysopoulos / Akeeba Ltd
//  Licensed under the MIT License. See license.txt in the project root for details.
//

import SwiftUI

/// Section C: the message's apparent delivery path, oldest to newest.
struct DeliveryPathView: View {
    let analysis: DeliveryPathAnalysis
    var onTrustHostnameMismatch: ((TrustedHostnameMismatch) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Delivery Path")
                .font(.headline)

            if analysis.hops.isEmpty {
                Text("This message has no Received headers, so its delivery path cannot be reconstructed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Oldest to newest. Hops outside infrastructure trusted in Settings can be forged by anyone who relayed this message — treat inconsistencies there as observations, not proof.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(analysis.hops.enumerated()), id: \.element.id) { index, hop in
                        DeliveryHopRow(hop: hop, isLast: index == analysis.hops.count - 1, onTrustHostnameMismatch: onTrustHostnameMismatch)
                    }
                }
            }
        }
    }
}

private struct DeliveryHopRow: View {
    let hop: DeliveryHop
    let isLast: Bool
    var onTrustHostnameMismatch: ((TrustedHostnameMismatch) -> Void)? = nil
    @State private var isExpanded = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                Circle()
                    .fill(dotColor)
                    .frame(width: 10, height: 10)
                    .padding(.top, 4)
                if !isLast {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.25))
                        .frame(width: 2)
                }
            }
            .frame(width: 10)

            DisclosureGroup(isExpanded: $isExpanded) {
                VStack(alignment: .leading, spacing: 6) {
                    if let claimed = hop.claimedFromHostname {
                        detail("Claimed hostname", claimed)
                    }
                    if let verified = hop.verifiedFromHostname {
                        detail("Verified hostname", verified)
                    }
                    if let ip = hop.fromIPAddress {
                        detail("Sending IP", ip)
                    }
                    if let by = hop.byHostname {
                        detail("Receiving host", by)
                    }
                    if let withProtocol = hop.withProtocol {
                        detail("Protocol", withProtocol)
                    }
                    if let tlsVersion = hop.tlsVersion {
                        detail("TLS", tlsVersion + (hop.tlsCipher.map { " (\($0))" } ?? ""))
                    }
                    ForEach(hop.flags) { flag in
                        HStack(spacing: 8) {
                            Label(flag.message, systemImage: flag.severity.symbolName)
                                .font(.caption)
                                .foregroundStyle(flag.severity.tintColor)
                            if let mismatch = flag.trustableHostnameMismatch, let onTrustHostnameMismatch {
                                Button("Mark as Safe") {
                                    onTrustHostnameMismatch(mismatch)
                                }
                                .buttonStyle(.link)
                                .font(.caption)
                            }
                        }
                    }
                    Text(hop.rawHeaderText)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
                .padding(.top, 6)
                .padding(.bottom, 12)
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(hop.claimedFromHostname ?? hop.fromIPAddress ?? "Unknown sender")
                            .font(.body.weight(.medium))
                        if let timestamp = hop.timestamp {
                            Text(timestamp.formatted(date: .abbreviated, time: .standard))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else if let raw = hop.timestampRaw {
                            Text("Unparsed date: \(raw)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if let worstSeverity {
                        Image(systemName: worstSeverity.symbolName)
                            .foregroundStyle(worstSeverity.tintColor)
                    }
                    trustBadge
                }
            }
        }
    }

    /// The most severe flag on this hop, if any — drives the leading dot's color and the
    /// trailing icon in the row's label, so a hop with only notices never looks as alarming as
    /// one with an actual warning.
    private var worstSeverity: ObservationSeverity? {
        hop.flags.map(\.severity).max()
    }

    private var dotColor: Color {
        if let worstSeverity { return worstSeverity.tintColor }
        if hop.isTrusted == true { return .green }
        return .secondary
    }

    @ViewBuilder
    private var trustBadge: some View {
        switch hop.isTrusted {
        case true:
            Text("Trusted").font(.caption2.weight(.semibold)).foregroundStyle(.green)
        case false:
            Text("Unverified").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
        case nil:
            EmptyView()
        }
    }

    @ViewBuilder
    private func detail(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(minWidth: 120, alignment: .leading)
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
        }
    }
}
