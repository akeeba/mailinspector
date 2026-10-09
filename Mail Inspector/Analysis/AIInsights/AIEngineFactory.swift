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
        case .remote:
            return remoteConfiguration(for: definition, settings: settings) != nil
        }
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

        case .remote:
            guard let (endpoint, apiKey, model) = remoteConfiguration(for: definition, settings: settings) else {
                return .unavailable(reason: unavailableReasonForRemote(definition, settings: settings))
            }
            return .ready(RemoteAIEngine(definition: definition, endpoint: endpoint, apiKey: apiKey, model: model, systemPrompt: systemPrompt))
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
}
