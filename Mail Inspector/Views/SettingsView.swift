import SwiftUI

/// App settings: trusted authentication servers and import limits.
struct SettingsView: View {
    @Environment(InspectorSettings.self) private var settings
    @State private var newAuthServID = ""

    var body: some View {
        Form {
            Section {
                if settings.trustedAuthServIDs.isEmpty {
                    Text("No trusted servers configured. Authentication results will be shown as Unknown until you add one.")
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
                Text("This is the only network request Mail Inspector ever makes: a weekly download of the public suffix list from publicsuffix.org, used to tell a subdomain (e.g. ministry.gov.gr) apart from an unrelated domain when checking DMARC alignment. No message content, addresses, or any other data is sent. Turning this off keeps the app fully offline and falls back to a small bundled list that covers fewer suffixes correctly.")
                    .font(.caption)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 560)
    }

    private func addAuthServID() {
        let trimmed = newAuthServID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !settings.trustedAuthServIDs.contains(trimmed) else { return }
        settings.trustedAuthServIDs.append(trimmed)
        newAuthServID = ""
    }
}
