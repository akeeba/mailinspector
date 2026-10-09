//
//  Mail Inspector
//
//  Copyright (c) 2026 Nicholas K. Dionysopoulos
//  Licensed under the MIT License. See license.txt in the project root for details.
//

import Foundation

/// Which wire format a remote provider speaks. Modeled after the proven provider architecture at
/// `~/Projects/grafida/grafida-ipad`: most hosted providers (and any self-hosted OpenAI-compatible
/// server — LM Studio, Ollama, vLLM, text-generation-webui, …) speak the same Chat Completions
/// shape; OpenAI's own Responses API and Anthropic's Messages API are each their own dialect.
nonisolated enum AIWireDialect: String, Sendable, Equatable {
    case openaiCompletions
    case openaiResponses
    case anthropic
}

nonisolated enum AIProviderAuthScheme: String, Sendable, Equatable {
    case bearer
    case xApiKey
    case none
}

nonisolated enum AIProviderKind: Sendable, Equatable {
    case onDevice
    case remote(AIWireDialect)
}

nonisolated struct AIProviderDefinition: Sendable, Equatable, Identifiable {
    let key: String
    let name: String
    let kind: AIProviderKind
    /// Pre-filled for providers with a fixed or conventional address (hosted providers, and
    /// LM Studio's default local port); empty for providers the user must configure themselves
    /// (Custom) or that have no network endpoint at all (On-Device).
    let defaultEndpoint: String
    let chatPath: String
    let modelsPath: String?
    let auth: AIProviderAuthScheme
    /// True when a request can be made with no API key at all — the common case for a bare local
    /// server with no auth configured (LM Studio, Custom pointed at Ollama/vLLM/etc).
    let apiKeyOptional: Bool
    /// Shown first in the picker with a "Recommended" badge.
    let isRecommended: Bool
    let isEndpointEditable: Bool

    var id: String { key }
}

/// The catalogue of AI backends offered in Settings. Display order (not alphabetical): LM Studio
/// first ("Recommended" — private, local, and far better at non-English text than the on-device
/// model), then On-Device Apple Intelligence (the zero-config default), then — once added — the
/// hosted commercial catalogue, with Custom always last as the escape hatch for anything else.
nonisolated enum AIProviderCatalog {
    static let onDevice = AIProviderDefinition(
        key: "apple_ondevice",
        name: "On-Device Apple Intelligence",
        kind: .onDevice,
        defaultEndpoint: "",
        chatPath: "",
        modelsPath: nil,
        auth: .none,
        apiKeyOptional: true,
        isRecommended: false,
        isEndpointEditable: false
    )

    static let lmStudio = AIProviderDefinition(
        key: "lmstudio",
        name: "LM Studio (Local)",
        kind: .remote(.openaiCompletions),
        defaultEndpoint: "http://localhost:1234/v1",
        chatPath: "/chat/completions",
        modelsPath: "/models",
        auth: .bearer,
        apiKeyOptional: true,
        isRecommended: true,
        isEndpointEditable: true
    )

    static let custom = AIProviderDefinition(
        key: "custom",
        name: "Custom (OpenAI-compatible)",
        kind: .remote(.openaiCompletions),
        defaultEndpoint: "",
        chatPath: "/chat/completions",
        modelsPath: "/models",
        auth: .bearer,
        apiKeyOptional: true,
        isRecommended: false,
        isEndpointEditable: true
    )

    // MARK: - Hosted commercial providers
    //
    // Endpoints/paths/dialects mirror the proven catalogue at
    // `~/Projects/grafida/grafida-ipad` (`AiCatalogue.swift`). All but OpenAI and Anthropic speak
    // the same `openaiCompletions` dialect `RemoteAIEngine` already implements for LM Studio.

    static let openAI = AIProviderDefinition(
        key: "openai",
        name: "OpenAI",
        kind: .remote(.openaiResponses),
        defaultEndpoint: "https://api.openai.com/v1",
        chatPath: "/responses",
        modelsPath: "/models",
        auth: .bearer,
        apiKeyOptional: false,
        isRecommended: false,
        isEndpointEditable: false
    )

    static let anthropic = AIProviderDefinition(
        key: "anthropic",
        name: "Anthropic",
        kind: .remote(.anthropic),
        defaultEndpoint: "https://api.anthropic.com/v1",
        chatPath: "/messages",
        modelsPath: "/models",
        auth: .xApiKey,
        apiKeyOptional: false,
        isRecommended: false,
        isEndpointEditable: false
    )

    static let cohere = AIProviderDefinition(
        key: "cohere",
        name: "Cohere",
        kind: .remote(.openaiCompletions),
        defaultEndpoint: "https://api.cohere.ai/compatibility/v1",
        chatPath: "/chat/completions",
        modelsPath: nil,
        auth: .bearer,
        apiKeyOptional: false,
        isRecommended: false,
        isEndpointEditable: false
    )

    static let deepSeek = AIProviderDefinition(
        key: "deepseek",
        name: "DeepSeek",
        kind: .remote(.openaiCompletions),
        defaultEndpoint: "https://api.deepseek.com/v1",
        chatPath: "/chat/completions",
        modelsPath: "/models",
        auth: .bearer,
        apiKeyOptional: false,
        isRecommended: false,
        isEndpointEditable: false
    )

    static let google = AIProviderDefinition(
        key: "google",
        name: "Google",
        kind: .remote(.openaiCompletions),
        defaultEndpoint: "https://generativelanguage.googleapis.com/v1beta/openai",
        chatPath: "/chat/completions",
        modelsPath: "/models",
        auth: .bearer,
        apiKeyOptional: false,
        isRecommended: false,
        isEndpointEditable: false
    )

    static let groq = AIProviderDefinition(
        key: "groq",
        name: "Groq",
        kind: .remote(.openaiCompletions),
        defaultEndpoint: "https://api.groq.com/openai/v1",
        chatPath: "/chat/completions",
        modelsPath: "/models",
        auth: .bearer,
        apiKeyOptional: false,
        isRecommended: false,
        isEndpointEditable: false
    )

    static let mistral = AIProviderDefinition(
        key: "mistral",
        name: "Mistral",
        kind: .remote(.openaiCompletions),
        defaultEndpoint: "https://api.mistral.ai/v1",
        chatPath: "/chat/completions",
        modelsPath: "/models",
        auth: .bearer,
        apiKeyOptional: false,
        isRecommended: false,
        isEndpointEditable: false
    )

    static let miniMax = AIProviderDefinition(
        key: "minimax",
        name: "MiniMax",
        kind: .remote(.openaiCompletions),
        defaultEndpoint: "https://api.minimax.io/v1",
        chatPath: "/chat/completions",
        modelsPath: "/models",
        auth: .bearer,
        apiKeyOptional: false,
        isRecommended: false,
        isEndpointEditable: false
    )

    static let openRouter = AIProviderDefinition(
        key: "openrouter",
        name: "OpenRouter",
        kind: .remote(.openaiCompletions),
        defaultEndpoint: "https://openrouter.ai/api/v1",
        chatPath: "/chat/completions",
        modelsPath: "/models",
        auth: .bearer,
        apiKeyOptional: false,
        isRecommended: false,
        isEndpointEditable: false
    )

    static let perplexity = AIProviderDefinition(
        key: "perplexity",
        name: "Perplexity",
        kind: .remote(.openaiCompletions),
        defaultEndpoint: "https://api.perplexity.ai",
        chatPath: "/chat/completions",
        modelsPath: nil,
        auth: .bearer,
        apiKeyOptional: false,
        isRecommended: false,
        isEndpointEditable: false
    )

    static let scaleway = AIProviderDefinition(
        key: "scaleway",
        name: "Scaleway",
        kind: .remote(.openaiCompletions),
        defaultEndpoint: "https://api.scaleway.ai/v1",
        chatPath: "/chat/completions",
        modelsPath: "/models",
        auth: .bearer,
        apiKeyOptional: false,
        isRecommended: false,
        isEndpointEditable: false
    )

    static let gitHub = AIProviderDefinition(
        key: "github",
        name: "GitHub",
        kind: .remote(.openaiCompletions),
        defaultEndpoint: "https://models.github.ai",
        chatPath: "/inference/chat/completions",
        modelsPath: "/catalog/models",
        auth: .bearer,
        apiKeyOptional: false,
        isRecommended: false,
        isEndpointEditable: false
    )

    /// The hosted commercial catalogue, alphabetically — sorted this way in the picker (after
    /// LM Studio and On-Device, before Custom), since there's no other natural ordering once
    /// there isn't a single "recommended" one among them.
    static let hostedCommercial: [AIProviderDefinition] = [
        anthropic, cohere, deepSeek, gitHub, google, groq, miniMax, mistral, openAI, openRouter, perplexity, scaleway,
    ]

    static let all: [AIProviderDefinition] = [lmStudio, onDevice] + hostedCommercial + [custom]

    static func definition(for key: String) -> AIProviderDefinition? {
        all.first { $0.key == key }
    }
}
