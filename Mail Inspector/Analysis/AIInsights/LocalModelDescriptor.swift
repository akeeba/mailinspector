//
//  Mail Inspector
//
//  Copyright (c) 2026 Nicholas K. Dionysopoulos / Akeeba Ltd
//  Licensed under the MIT License. See license.txt in the project root for details.
//

import Foundation

/// Describes one downloadable MLX model offered as an on-device AI-analysis provider. Modeled
/// after the proven catalogue at `~/Projects/grafida/grafida-ipad`
/// (`LocalModelDescriptor.swift`/`LocalModelCatalogue.swift`) — one provider is one model, same
/// as every other entry in `AIProviderCatalog`. See `.claude/docs/on-device-mlx-llm.md` for why
/// these specific two models and these specific thresholds.
nonisolated struct LocalModelDescriptor: Sendable, Equatable, Identifiable {
    /// Matches the corresponding `AIProviderDefinition.key` in `AIProviderCatalog`.
    let key: String
    let name: String
    /// Hugging Face "owner/name" repository.
    let repository: String
    /// A pinned commit SHA, not a branch name — keeps a download reproducible even if the
    /// repository's default branch changes later.
    let revision: String
    let downloadBytes: Int64
    /// Marketed unified-memory figure (8GB, 16GB, ...) required to run this model — see
    /// `LocalModelSuitability` for how this is compared against the real reported figure.
    let memoryGateBytes: Int64
    let contextTokens: Int
    let licenceIdentifier: String
    let licenceURL: String
    /// Whether this model's chat template free-ranges into unbounded chain-of-thought prose
    /// instead of answering directly, unless explicitly told not to via the template's
    /// `enable_thinking` flag. Confirmed hands-on for Qwen3.5 (see
    /// `.claude/docs/on-device-mlx-llm.md`): left at its default, it burned an entire 400-token
    /// budget narrating "Thinking Process:" and never produced the requested JSON at all.
    let disablesThinkingViaTemplate: Bool

    var id: String { key }

    /// Forwarded verbatim into `ChatSession`'s `additionalContext`, which feeds this model's
    /// jinja chat template rendering context — `nil` for a model whose template doesn't need it
    /// (Ternary Bonsai's template has no open-thinking branch at all).
    var chatTemplateContext: [String: any Sendable]? {
        disablesThinkingViaTemplate ? ["enable_thinking": false] : nil
    }
}
