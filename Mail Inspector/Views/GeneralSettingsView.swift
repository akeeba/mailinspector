//
//  Mail Inspector
//
//  Copyright (c) 2026 Nicholas K. Dionysopoulos / Akeeba Ltd
//  Licensed under the MIT License. See license.txt in the project root for details.
//

import SwiftUI

/// General preferences: import limits, domain alignment data, noteworthy observations, and report export.
struct GeneralSettingsView: View {
    @Environment(InspectorSettings.self) private var settings

    var body: some View {
        Form {
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
        .frame(width: 480)
    }
}
