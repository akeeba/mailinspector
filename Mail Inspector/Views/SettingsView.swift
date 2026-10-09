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
    @State private var apiKeyInput = ""
    @State private var fetchedModels: [String] = []
    @State private var isFetchingModels = false
    @State private var modelFetchError: String?

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
                                Text("for \(entry.recipient)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button {
                                settings.removeTrustedReplyToDomain(entry.domain, forRecipient: entry.recipient)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Remove \(entry.domain) for \(entry.recipient)")
                        }
                    }
                }
            } header: {
                Text("Trusted Reply-To Domains")
            } footer: {
                Text("Some recipients deliberately route replies to a different domain (e.g. a sales alias whose replies go to a separate help desk) — this app would otherwise flag that as a Reply-To mismatch every time. Entries here suppress that specific notice for that specific recipient.")
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
                Toggle("Show brand images", isOn: Binding(
                    get: { settings.showBrandImages },
                    set: { settings.showBrandImages = $0 }
                ))
                if settings.showBrandImages {
                    Toggle("Hide brand images for messages without a spam score", isOn: Binding(
                        get: { settings.hideBrandImagesForMessagesWithoutSpamScore },
                        set: { settings.hideBrandImagesForMessagesWithoutSpamScore = $0 }
                    ))
                    Stepper(value: Binding(
                        get: { settings.hideBrandImagesAboveSpamThreshold },
                        set: { settings.hideBrandImagesAboveSpamThreshold = min(100, max(0, $0)) }
                    ), in: 0...100, step: 5) {
                        Text("Hide brand images above spam score: \(Int(settings.hideBrandImagesAboveSpamThreshold))%")
                    }
                }
            } header: {
                Text("Brand Images (BIMI)")
            } footer: {
                Text(settings.showBrandImages
                    ? "Looks up and displays the sender's published brand logo next to their identity, only when DMARC is a trusted pass. Fetching and rendering a remote image — even a logo the sender's own domain publishes — could be used as an attack vector against an unpatched vulnerability in macOS's image-decoding pipeline, the same risk as opening an image attachment from an untrusted sender. Only the logo's own domain is contacted, nothing else. The two options below only apply when a spam score is or isn't available, and are ignored entirely if \"Trust server spam headers\" is off and this message has no score."
                    : "Off by default. Looks up and displays the sender's published brand logo next to their identity, only when DMARC is a trusted pass. Fetching and rendering a remote image — even a logo the sender's own domain publishes — could be used as an attack vector against an unpatched vulnerability in macOS's image-decoding pipeline, the same risk as opening an image attachment from an untrusted sender.")
                    .font(.caption)
            }

            Section {
                Toggle("Analyze messages with AI", isOn: Binding(
                    get: { settings.isAIInsightsEnabled },
                    set: { settings.isAIInsightsEnabled = $0 }
                ))
                if settings.isAIInsightsEnabled {
                    Picker("Provider", selection: Binding(
                        get: { settings.aiActiveProviderKey },
                        set: { newKey in
                            settings.aiActiveProviderKey = newKey
                            apiKeyInput = ""
                            fetchedModels = []
                            modelFetchError = nil
                        }
                    )) {
                        ForEach(AIProviderCatalog.all) { provider in
                            Text(provider.isRecommended ? "\(provider.name) — Recommended" : provider.name)
                                .tag(provider.key)
                        }
                    }

                    if let selectedProvider {
                        providerConfigurationFields(for: selectedProvider)

                        Toggle("Allow including message text in chat", isOn: Binding(
                            get: { settings.allowIncludingMessageTextInAIChat },
                            set: { settings.allowIncludingMessageTextInAIChat = $0 }
                        ))
                    }
                }
            } header: {
                Text("AI Message Analysis")
            } footer: {
                Text(aiSectionFooterText)
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
        .frame(width: 480, height: 1420)
    }

    private struct TrustedReplyToEntry: Hashable {
        let recipient: String
        let domain: String
    }

    /// Flattens `trustedReplyToDomainsByRecipient`'s `[recipient: [domain]]` shape into one row
    /// per (recipient, domain) pair, sorted for a stable display order.
    private var trustedReplyToEntries: [TrustedReplyToEntry] {
        var entries: [TrustedReplyToEntry] = []
        for (recipient, domains) in settings.trustedReplyToDomainsByRecipient {
            for domain in domains {
                entries.append(TrustedReplyToEntry(recipient: recipient, domain: domain))
            }
        }
        return entries.sorted { lhs, rhs in
            guard lhs.recipient == rhs.recipient else { return lhs.recipient < rhs.recipient }
            return lhs.domain < rhs.domain
        }
    }

    private var selectedProvider: AIProviderDefinition? {
        AIProviderCatalog.definition(for: settings.aiActiveProviderKey)
    }

    private var aiSectionFooterText: String {
        guard settings.isAIInsightsEnabled else {
            return "Off disables the legitimacy score, analysis, and chat throughout the report."
        }
        switch selectedProvider?.kind {
        case .onDevice:
            return "Requires macOS 27 and Apple Intelligence enabled on eligible hardware. Runs entirely on-device: a legitimacy score and a short analysis are generated once per message from the signals already shown elsewhere in this report (SPF/DKIM/DMARC, delivery path, spam score) — never the raw headers or message body — plus a chat for follow-up questions. It's a model's opinion, not a verdict; it can be confidently wrong. When \"Allow including message text in chat\" is on, a chat question can optionally attach a raw, undecoded excerpt of the message's own text — this app never otherwise decodes the body, and that excerpt can look like encoded gibberish for most real-world messages."
        case .remote:
            return "Sends the signal digest shown elsewhere in this report (SPF/DKIM/DMARC, delivery path, spam score) — never the raw headers — to the endpoint below for each message, plus any chat questions you ask. A locally-hosted server (like LM Studio, at the default address) never leaves this Mac; any other address is a real third party receiving that data. When \"Allow including message text in chat\" is on, a chat question can optionally attach a raw, undecoded excerpt of the message's own text, which goes to the same destination. It's a model's opinion, not a verdict; it can be confidently wrong."
        case nil:
            return "No provider selected."
        }
    }

    @ViewBuilder
    private func providerConfigurationFields(for provider: AIProviderDefinition) -> some View {
        if provider.isEndpointEditable {
            TextField("Endpoint URL", text: Binding(
                get: { settings.aiProviderEndpoints[provider.key] ?? provider.defaultEndpoint },
                set: { settings.aiProviderEndpoints[provider.key] = $0 }
            ))
            .textFieldStyle(.roundedBorder)
        }

        if provider.kind != .onDevice {
            let hasStoredKey = AIKeychainStore.get(forProvider: provider.key) != nil
            HStack {
                SecureField(
                    hasStoredKey ? "API key saved — leave blank to keep it" : (provider.apiKeyOptional ? "API key (optional)" : "API key"),
                    text: $apiKeyInput
                )
                .textFieldStyle(.roundedBorder)
                Button("Save") {
                    AIKeychainStore.set(apiKeyInput, forProvider: provider.key)
                    apiKeyInput = ""
                }
                .disabled(apiKeyInput.isEmpty)
                if hasStoredKey {
                    Button("Clear") {
                        AIKeychainStore.delete(forProvider: provider.key)
                    }
                }
            }

            HStack {
                TextField("Model name", text: Binding(
                    get: { settings.aiProviderModelNames[provider.key] ?? "" },
                    set: { settings.aiProviderModelNames[provider.key] = $0 }
                ))
                .textFieldStyle(.roundedBorder)
                if provider.modelsPath != nil {
                    Button(isFetchingModels ? "Fetching…" : "Fetch Models") {
                        fetchModels(for: provider)
                    }
                    .disabled(isFetchingModels)
                }
            }

            if !fetchedModels.isEmpty {
                Picker("Fetched models", selection: Binding(
                    get: { settings.aiProviderModelNames[provider.key] ?? "" },
                    set: { settings.aiProviderModelNames[provider.key] = $0 }
                )) {
                    ForEach(fetchedModels, id: \.self) { modelName in
                        Text(modelName).tag(modelName)
                    }
                }
                .labelsHidden()
            }
            if let modelFetchError {
                Text(modelFetchError)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func fetchModels(for provider: AIProviderDefinition) {
        isFetchingModels = true
        modelFetchError = nil
        fetchedModels = []

        let endpoint = settings.aiProviderEndpoints[provider.key] ?? provider.defaultEndpoint
        let apiKey = apiKeyInput.isEmpty ? AIKeychainStore.get(forProvider: provider.key) : apiKeyInput
        let engine = RemoteAIEngine(definition: provider, endpoint: endpoint, apiKey: apiKey, model: "", systemPrompt: "")

        Task {
            do {
                fetchedModels = try await engine.listAvailableModels()
                if fetchedModels.isEmpty {
                    modelFetchError = "The provider didn't list any models."
                }
            } catch {
                modelFetchError = (error as? AIEngineError)?.message ?? "Couldn't fetch models."
            }
            isFetchingModels = false
        }
    }

    private func addAuthServID() {
        let trimmed = newAuthServID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !settings.trustedAuthServIDs.contains(trimmed) else { return }
        settings.trustedAuthServIDs.append(trimmed)
        newAuthServID = ""
    }
}
