//
//  Mail Inspector
//
//  Copyright (c) 2026 Nicholas K. Dionysopoulos
//  Licensed under the MIT License. See license.txt in the project root for details.
//

import SwiftUI

/// App settings: trusted authentication servers and import limits.
struct SettingsView: View {
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
                Stepper(value: Binding(
                    get: { settings.maxMessageSizeBytes / (1024 * 1024) },
                    set: { settings.maxMessageSizeBytes = max(1, $0) * 1024 * 1024 }
                ), in: 1...200) {
                    Text("Maximum message size: \(settings.maxMessageSizeBytes / (1024 * 1024)) MB")
                }
            } header: {
                Text("Import Limits")
            } footer: {
                Text("Messages larger than this are rejected before parsing, to bound memory use for untrusted input.")
                    .font(.caption)
            }

            Section {
                Toggle("Keep the public suffix list up to date", isOn: Binding(
                    get: { settings.isPublicSuffixListUpdateEnabled },
                    set: { settings.isPublicSuffixListUpdateEnabled = $0 }
                ))
                if let lastUpdated = PublicSuffixList.shared.lastUpdated {
                    LabeledContent("Last updated") {
                        Text(lastUpdated.formatted(date: .abbreviated, time: .shortened))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    LabeledContent("Last updated") {
                        Text("Never — using the bundled fallback list")
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Domain Alignment Data")
            } footer: {
                Text("A weekly download of the public suffix list from publicsuffix.org, used to tell a subdomain (e.g. ministry.gov.gr) apart from an unrelated domain when checking DMARC alignment. No message content, addresses, or any other data is sent. Turning this off keeps the app fully offline and falls back to a small bundled list that covers fewer suffixes correctly.")
                    .font(.caption)
            }

            Section {
                Toggle("Show Noteworthy Observations", isOn: Binding(
                    get: { settings.isObservationsSummaryEnabled },
                    set: { settings.isObservationsSummaryEnabled = $0 }
                ))
            } header: {
                Text("Noteworthy Observations")
            } footer: {
                Text("Off by default. When on, a summary panel highlights sender-identity discrepancies and delivery-path anomalies. In practice, most delivery-path flags are ordinary hops within a legitimate sender's own SaaS infrastructure (for example, an app server relaying through an internal mail sender before reaching the public internet) — normal for most legitimate email, not a sign of anything wrong.")
                    .font(.caption)
            }

            Section {
                Toggle("Trust server spam headers", isOn: Binding(
                    get: { settings.trustServerSpamHeaders },
                    set: { settings.trustServerSpamHeaders = $0 }
                ))
            } header: {
                Text("Spam Filtering")
            } footer: {
                Text("When on, a message's spam-filter headers (X-Spam-Score, Exchange's Spam Confidence Level, etc.) are shown as a likelihood gauge. Off by default: unlike SPF/DKIM/DMARC these headers follow no standard, their scoring is entirely filter-specific, and the gauge only rescales a number a filter already reported — it's never something this app determined independently.")
                    .font(.caption)
            }

            Section {
                Picker("Page size", selection: Binding(
                    get: { settings.reportPageSize },
                    set: { settings.reportPageSize = $0 }
                )) {
                    ForEach(ReportPageSize.allCases) { pageSize in
                        Text(pageSize.displayName).tag(pageSize)
                    }
                }
            } header: {
                Text("Report Export (⌘E / ⇧⌘E)")
            } footer: {
                Text("The page size used when exporting or sharing the report as a PDF. The report is automatically paginated to fit, with a page number in the footer of each page.")
                    .font(.caption)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 940)
    }

    private func addAuthServID() {
        let trimmed = newAuthServID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !settings.trustedAuthServIDs.contains(trimmed) else { return }
        settings.trustedAuthServIDs.append(trimmed)
        newAuthServID = ""
    }
}
