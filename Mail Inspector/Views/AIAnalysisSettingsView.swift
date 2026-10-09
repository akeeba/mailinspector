//
//  Mail Inspector
//
//  Copyright (c) 2026 Nicholas K. Dionysopoulos / Akeeba Ltd
//  Licensed under the MIT License. See license.txt in the project root for details.
//

import SwiftUI

/// AI Analysis preferences: enabling AI-generated message insights and configuring a provider.
struct AIAnalysisSettingsView: View {
    @Environment(InspectorSettings.self) private var settings
    @State private var apiKeyInput = ""
    @State private var fetchedModels: [String] = []
    @State private var isFetchingModels = false
    @State private var modelFetchError: String?
    /// Bumped after every install/delete so the on-device-model UI (which reads
    /// `LocalModelStore.isInstalled` directly, not from any `@Observable` state) re-renders.
    @State private var modelInventoryVersion = 0
    @State private var downloadProgressByModelKey: [String: (completed: Int64, total: Int64)] = [:]
    @State private var downloadErrorByModelKey: [String: String] = [:]

    var body: some View {
        Form {
            Section {
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

                if let selectedProvider, selectedProvider.kind != .disabled {
                    providerConfigurationFields(for: selectedProvider)

                    Toggle("Allow including message text in chat", isOn: Binding(
                        get: { settings.allowIncludingMessageTextInAIChat },
                        set: { settings.allowIncludingMessageTextInAIChat = $0 }
                    ))
                }
            } header: {
                Text("AI Message Analysis")
            } footer: {
                Text(aiSectionFooterText)
                    .font(.caption)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
    }

    private var selectedProvider: AIProviderDefinition? {
        AIProviderCatalog.definition(for: settings.aiActiveProviderKey)
    }

    private var aiSectionFooterText: String {
        switch selectedProvider?.kind {
        case .disabled, nil:
            return "Off disables the legitimacy score, analysis, and chat throughout the report."
        case .onDevice:
            return "Requires macOS 27 and Apple Intelligence enabled on eligible hardware. Runs entirely on-device: a legitimacy score and a short analysis are generated once per message from the signals already shown elsewhere in this report (SPF/DKIM/DMARC, delivery path, spam score) — never the raw headers or message body — plus a chat for follow-up questions. It's a model's opinion, not a verdict; it can be confidently wrong. When \"Allow including message text in chat\" is on, a chat question can optionally attach a raw, undecoded excerpt of the message's own text — this app never otherwise decodes the body, and that excerpt can look like encoded gibberish for most real-world messages."
        case .localMlx:
            return "Requires a Mac with an Apple Silicon processor, and enough free unified memory and disk space for the model you pick below. Downloaded once, then runs entirely on-device — nothing ever leaves the Mac, same as Apple's on-device option, but without needing Apple Intelligence or macOS 27. It's a model's opinion, not a verdict; it can be confidently wrong."
        case .remote:
            return "Requires a compatible service, self-hosted (like LM Studio) or online. Sends the signal digest shown elsewhere in this report (SPF/DKIM/DMARC, delivery path, spam score) — never the raw headers — to the endpoint below for each message, plus any chat questions you ask. A locally-hosted server (like LM Studio, at the default address) never leaves this Mac; any other address is a real third party receiving that data. When \"Allow including message text in chat\" is on, a chat question can optionally attach a raw, undecoded excerpt of the message's own text, which goes to the same destination. It's a model's opinion, not a verdict; it can be confidently wrong."
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

        if case .localMlx(let modelKey) = provider.kind, let descriptor = LocalModelCatalogue.descriptor(for: modelKey) {
            // Reading `modelInventoryVersion` here (even though it's unused beyond that) is what
            // makes this view re-render after `startDownload`/`deleteModel` change what's on disk.
            let _ = modelInventoryVersion
            localMlxModelFields(for: descriptor)
        }

        if case .remote = provider.kind {
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

    @ViewBuilder
    private func localMlxModelFields(for descriptor: LocalModelDescriptor) -> some View {
        let decision = LocalModelSuitability.decision(for: descriptor)
        if decision != .allowed {
            Text(decision.unavailableReason ?? "Not available on this Mac.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if LocalModelStore.shared.isInstalled(descriptor) {
            HStack {
                Label("Downloaded", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Spacer()
                Button("Remove", role: .destructive) {
                    deleteModel(descriptor)
                }
            }
        } else if let progress = downloadProgressByModelKey[descriptor.key] {
            VStack(alignment: .leading, spacing: 4) {
                ProgressView(value: Double(progress.completed), total: Double(max(progress.total, 1)))
                Text("Downloading \(descriptor.name)… \(formattedBytes(progress.completed)) of \(formattedBytes(progress.total))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Button("Download Model (\(formattedBytes(descriptor.downloadBytes)))") {
                    startDownload(descriptor)
                }
                if let error = downloadErrorByModelKey[descriptor.key] {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func formattedBytes(_ count: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: count)
    }

    private func startDownload(_ descriptor: LocalModelDescriptor) {
        downloadErrorByModelKey[descriptor.key] = nil
        downloadProgressByModelKey[descriptor.key] = (0, descriptor.downloadBytes)
        Task {
            do {
                for try await event in LocalModelDownloader.shared.download(descriptor) {
                    switch event {
                    case .progress(let completed, let total):
                        downloadProgressByModelKey[descriptor.key] = (completed, total)
                    case .installed:
                        downloadProgressByModelKey[descriptor.key] = nil
                        modelInventoryVersion += 1
                    }
                }
            } catch {
                downloadProgressByModelKey[descriptor.key] = nil
                downloadErrorByModelKey[descriptor.key] = "Download failed: \(error.localizedDescription)"
            }
        }
    }

    private func deleteModel(_ descriptor: LocalModelDescriptor) {
        try? LocalModelStore.shared.delete(descriptor)
        modelInventoryVersion += 1
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
}
