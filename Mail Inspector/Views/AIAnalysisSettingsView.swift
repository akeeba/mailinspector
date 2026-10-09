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

    var body: some View {
        Form {
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
        }
        .formStyle(.grouped)
        .frame(width: 480)
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
}
