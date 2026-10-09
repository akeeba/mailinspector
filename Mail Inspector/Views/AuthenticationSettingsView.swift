//
//  Mail Inspector
//
//  Copyright (c) 2026 Nicholas K. Dionysopoulos / Akeeba Ltd
//  Licensed under the MIT License. See license.txt in the project root for details.
//

import SwiftUI

/// Authentication preferences: trusted Authentication-Results servers and trust exceptions
/// for Reply-To and delivery-hop hostname mismatches.
struct AuthenticationSettingsView: View {
    @Environment(InspectorSettings.self) private var settings
    @State private var newAuthServID = ""

    var body: some View {
        Form {
            Section {
                Toggle("Trust all Authentication-Results reports by default", isOn: Binding(
                    get: { settings.trustAllAuthenticationResultsByDefault },
                    set: { settings.trustAllAuthenticationResultsByDefault = $0 }
                ))
            } footer: {
                Text("When on, every Authentication-Results header is shown as a trusted report, regardless of which server added it. Turn this off to require explicitly trusting each authserv-id below instead — useful if you want to be certain only servers you've vetted drive the Pass/Fail verdicts you see.")
                    .font(.caption)
            }

            Section {
                if settings.trustedAuthServIDs.isEmpty {
                    Text(settings.trustAllAuthenticationResultsByDefault
                        ? "Not used while \"Trust all Authentication-Results reports by default\" is on."
                        : "No trusted servers configured. Authentication results will be shown as Unknown until you add one.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                ForEach(settings.trustedAuthServIDs, id: \.self) { authServID in
                    HStack {
                        Text(authServID)
                            .textSelection(.enabled)
                        Spacer()
                        Button {
                            settings.trustedAuthServIDs.removeAll { $0 == authServID }
                        } label: {
                            Image(systemName: "minus.circle.fill")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Remove \(authServID)")
                    }
                }
                HStack {
                    TextField("mx.example.com", text: $newAuthServID)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(addAuthServID)
                    Button("Add", action: addAuthServID)
                        .disabled(newAuthServID.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } header: {
                Text("Trusted Authentication Servers")
            } footer: {
                Text("Enter the authserv-id of a mail server you trust to report SPF, DKIM, and DMARC results honestly — this is the name shown before the first semicolon in its Authentication-Results header. Matching this name alone does not prove a result is genuine: any server along the delivery path could write an Authentication-Results header claiming to be one of these. Trust ultimately depends on your receiving infrastructure stripping forged headers before the message reached you.")
                    .font(.caption)
            }

            Section {
                if trustedReplyToEntries.isEmpty {
                    Text("None yet. Use \u{201c}Mark as Safe\u{201d} next to a Reply-To mismatch in a message's report to add one here.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(trustedReplyToEntries, id: \.self) { entry in
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(entry.domain)
                                    .textSelection(.enabled)
                                Text("for mail from \(entry.sender)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button {
                                settings.removeTrustedReplyToDomain(entry.domain, forSender: entry.sender)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Remove \(entry.domain) for mail from \(entry.sender)")
                        }
                    }
                }
            } header: {
                Text("Trusted Reply-To Domains")
            } footer: {
                Text("Some senders deliberately route replies to a different domain (e.g. a vendor whose replies go to a separate help desk) — this app would otherwise flag that as a Reply-To mismatch every time. Entries here suppress that specific notice for mail from that specific sender, regardless of which of your addresses it was sent to.")
                    .font(.caption)
            }

            Section {
                if settings.trustedHostnameMismatches.isEmpty {
                    Text("None yet. Use \u{201c}Mark as Safe\u{201d} next to a delivery-hop hostname mismatch in a message's report to add one here.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(settings.trustedHostnameMismatches, id: \.self) { entry in
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(entry.claimed)
                                    .textSelection(.enabled)
                                Text("verified as \(entry.verified)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button {
                                settings.removeTrustedHostnameMismatch(entry)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Remove trusted hostname pair \(entry.claimed)")
                        }
                    }
                }
            } header: {
                Text("Trusted Delivery-Hop Hostnames")
            } footer: {
                Text("Some intermediate mail servers (e.g. an external-facing proxy in front of an internal relay) legitimately claim a hostname that differs from its reverse-DNS name — this app would otherwise flag that as a forged-looking mismatch every time. Entries here suppress that specific warning for that specific claimed/verified pair.")
                    .font(.caption)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
    }

    private struct TrustedReplyToEntry: Hashable {
        let sender: String
        let domain: String
    }

    /// Flattens `trustedReplyToDomainsBySender`'s `[sender: [domain]]` shape into one row per
    /// (sender, domain) pair, sorted for a stable display order.
    private var trustedReplyToEntries: [TrustedReplyToEntry] {
        var entries: [TrustedReplyToEntry] = []
        for (sender, domains) in settings.trustedReplyToDomainsBySender {
            for domain in domains {
                entries.append(TrustedReplyToEntry(sender: sender, domain: domain))
            }
        }
        return entries.sorted { lhs, rhs in
            guard lhs.sender == rhs.sender else { return lhs.sender < rhs.sender }
            return lhs.domain < rhs.domain
        }
    }

    private func addAuthServID() {
        let trimmed = newAuthServID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !settings.trustedAuthServIDs.contains(trimmed) else { return }
        settings.trustedAuthServIDs.append(trimmed)
        newAuthServID = ""
    }
}
