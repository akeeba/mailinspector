//
//  Mail Inspector
//
//  Copyright (c) 2026 Nicholas K. Dionysopoulos / Akeeba Ltd
//  Licensed under the MIT License. See license.txt in the project root for details.
//

import Foundation

/// The result of trying to resolve the currently-configured provider into a usable engine.
/// Holding `any AIAnalysisEngine` here carries no availability requirement of its own — the
/// protocol has none — so this type, like `AIAnalysisEngine` itself, is safe to use from
/// always-available code even though one of its possible concrete payloads (`OnDeviceAIEngine`)
/// requires macOS 27.
nonisolated enum AIEngineAvailability {
    case ready(any AIAnalysisEngine)
    case unavailable(reason: String)
}

/// Decides which engine should actually be used right now, based on `InspectorSettings`'s active
/// provider selection. Carries no `@available` annotation itself — like `AIInsightsAvailability`,
/// it guards its one macOS-27-only reference internally — so call sites never need their own
/// `if #available` just to ask "what should I use?"
enum AIEngineFactory {
    /// A cheap readiness check that never constructs an engine — for call sites that only need
    /// to know whether *something* would be ready right now, not to actually use it (e.g. the
    /// summary block's score-pending gating, re-evaluated on every render).
    @MainActor
    static func isActiveProviderReady(settings: InspectorSettings) -> Bool {
        guard let definition = AIProviderCatalog.definition(for: settings.aiActiveProviderKey) else { return false }
        switch definition.kind {
        case .disabled:
            return false
        case .onDevice:
            return AIInsightsAvailability.current == .available
        case .localMlx(let modelKey):
            return isLocalMlxModelReady(modelKey: modelKey)
        case .remote:
            return remoteConfiguration(for: definition, settings: settings) != nil
        case .systemOne:
            return systemOneConfiguration(for: definition, settings: settings) != nil
        }
    }

    /// Ready means suitable for this Mac *and* already downloaded — a model that could run here
    /// but hasn't been fetched yet in Settings is not ready, same as a remote provider missing
    /// its endpoint or API key.
    @MainActor
    private static func isLocalMlxModelReady(modelKey: String) -> Bool {
        guard let descriptor = LocalModelCatalogue.descriptor(for: modelKey) else { return false }
        guard LocalModelSuitability.decision(for: descriptor) == .allowed else { return false }
        return LocalModelStore.shared.isInstalled(descriptor)
    }

    @MainActor
    static func resolveActiveEngine(settings: InspectorSettings, systemPrompt: String) -> AIEngineAvailability {
        guard let definition = AIProviderCatalog.definition(for: settings.aiActiveProviderKey) else {
            return .unavailable(reason: "No AI provider is configured.")
        }

        switch definition.kind {
        case .disabled:
            return .unavailable(reason: "AI analysis is turned off — pick a provider in Settings.")

        case .onDevice:
            if case .unavailable(let reason) = AIInsightsAvailability.current {
                return .unavailable(reason: reason)
            }
            guard #available(macOS 27, *) else {
                return .unavailable(reason: "Requires macOS 27 or later.")
            }
            return .ready(OnDeviceAIEngine(systemPrompt: systemPrompt))

        case .localMlx(let modelKey):
            guard let descriptor = LocalModelCatalogue.descriptor(for: modelKey) else {
                return .unavailable(reason: "This on-device model is no longer offered.")
            }
            let decision = LocalModelSuitability.decision(for: descriptor)
            guard decision == .allowed else {
                return .unavailable(reason: decision.unavailableReason ?? "This Mac can't run \(descriptor.name).")
            }
            guard LocalModelStore.shared.isInstalled(descriptor) else {
                return .unavailable(reason: "\(descriptor.name) hasn't been downloaded yet — download it in Settings.")
            }
            return .ready(MLXAIEngine(descriptor: descriptor, systemPrompt: systemPrompt))

        case .remote:
            guard let (endpoint, apiKey, model) = remoteConfiguration(for: definition, settings: settings) else {
                return .unavailable(reason: unavailableReasonForRemote(definition, settings: settings))
            }
            return .ready(RemoteAIEngine(definition: definition, endpoint: endpoint, apiKey: apiKey, model: model, systemPrompt: systemPrompt))

        case .systemOne:
            guard let (endpoint, apiKey, prompt, contextLength) = systemOneConfiguration(for: definition, settings: settings) else {
                return .unavailable(reason: unavailableReasonForSystemOne(definition, settings: settings))
            }
            return .ready(SystemOneAIEngine(definition: definition, endpoint: endpoint, apiKey: apiKey, prompt: prompt, contextLength: contextLength))
        }
    }

    /// `nil` if anything required is still missing; otherwise the resolved (endpoint, apiKey,
    /// model) this provider is ready to be used with.
    @MainActor
    private static func remoteConfiguration(for definition: AIProviderDefinition, settings: InspectorSettings) -> (endpoint: String, apiKey: String?, model: String)? {
        let endpoint = settings.aiProviderEndpoints[definition.key] ?? definition.defaultEndpoint
        guard !endpoint.isEmpty else { return nil }

        let apiKey = AIKeychainStore.get(forProvider: definition.key)
        guard apiKey != nil || definition.apiKeyOptional else { return nil }

        let model = settings.aiProviderModelNames[definition.key] ?? ""
        guard !model.isEmpty else { return nil }

        return (endpoint, apiKey, model)
    }

    @MainActor
    private static func unavailableReasonForRemote(_ definition: AIProviderDefinition, settings: InspectorSettings) -> String {
        let endpoint = settings.aiProviderEndpoints[definition.key] ?? definition.defaultEndpoint
        guard !endpoint.isEmpty else {
            return "\(definition.name) needs an endpoint URL — add one in Settings."
        }
        let hasKey = AIKeychainStore.get(forProvider: definition.key) != nil
        guard hasKey || definition.apiKeyOptional else {
            return "\(definition.name) needs an API key — add one in Settings."
        }
        return "\(definition.name) needs a model name — add one in Settings."
    }

    /// `nil` if anything required is still missing; otherwise the resolved (endpoint, apiKey,
    /// prompt, contextLength) this System One-family provider is ready to be used with. Unlike
    /// `remoteConfiguration`, there's no model name to resolve — System One has no model picker —
    /// and `contextLength` is `nil` whenever the endpoint isn't user-editable (Jev's own fixed,
    /// hosted endpoint never needs one).
    @MainActor
    private static func systemOneConfiguration(for definition: AIProviderDefinition, settings: InspectorSettings) -> (endpoint: String, apiKey: String?, prompt: String, contextLength: Int?)? {
        let endpoint = settings.aiProviderEndpoints[definition.key] ?? definition.defaultEndpoint
        guard !endpoint.isEmpty else { return nil }

        let apiKey = AIKeychainStore.get(forProvider: definition.key)
        guard apiKey != nil || definition.apiKeyOptional else { return nil }

        let prompt = settings.aiProviderPrompts[definition.key] ?? SystemOneAIEngine.defaultPrompt
        guard !prompt.isEmpty else { return nil }

        let contextLength: Int? = definition.isEndpointEditable
            ? max(0, min(1_000_000, settings.aiProviderContextLengths[definition.key] ?? 8192))
            : nil

        return (endpoint, apiKey, prompt, contextLength)
    }

    @MainActor
    private static func unavailableReasonForSystemOne(_ definition: AIProviderDefinition, settings: InspectorSettings) -> String {
        let endpoint = settings.aiProviderEndpoints[definition.key] ?? definition.defaultEndpoint
        guard !endpoint.isEmpty else {
            return "\(definition.name) needs an endpoint URL — add one in Settings."
        }
        let hasKey = AIKeychainStore.get(forProvider: definition.key) != nil
        guard hasKey || definition.apiKeyOptional else {
            return "\(definition.name) needs an API key — add one in Settings."
        }
        return "\(definition.name) needs a prompt — add one in Settings."
    }
}
