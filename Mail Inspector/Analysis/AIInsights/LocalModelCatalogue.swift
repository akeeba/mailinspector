//
//  Mail Inspector
//
//  Copyright (c) 2026 Nicholas K. Dionysopoulos / Akeeba Ltd
//  Licensed under the MIT License. See license.txt in the project root for details.
//

import Foundation

/// The on-device MLX models Mail Inspector offers, chosen and JSON-schema-tested as described in
/// `.claude/docs/on-device-mlx-llm.md`. Matches the exact repository/revision pins already proven
/// at `~/Projects/grafida/grafida-ipad`.
nonisolated enum LocalModelCatalogue {
    /// The smaller, broadly-available model — works on any Apple Silicon Mac, since none has
    /// ever shipped with less than 8GB of unified memory. Needs `enable_thinking: false` forced
    /// via its chat template or it never produces the score JSON at all — see
    /// `LocalModelDescriptor.disablesThinkingViaTemplate`.
    static let qwen35_2b = LocalModelDescriptor(
        key: "mlx_qwen35_2b",
        name: "Qwen 3.5 2B (On This Device)",
        repository: "mlx-community/Qwen3.5-2B-MLX-4bit",
        revision: "93760be4f1f69842a46bc13dbdc0f19e291392a3",
        downloadBytes: 1_720_000_000,
        memoryGateBytes: 8 * 1_073_741_824,
        contextTokens: 262_144,
        licenceIdentifier: "Apache-2.0",
        licenceURL: "https://huggingface.co/mlx-community/Qwen3.5-2B-MLX-4bit",
        disablesThinkingViaTemplate: true
    )

    /// The larger, more capable 1-bit-class (ternary) model — gated at 16GB of unified memory.
    /// Its chat template has no open-thinking branch at all, so it needs no special handling.
    static let ternaryBonsai8b = LocalModelDescriptor(
        key: "mlx_ternary_bonsai_8b",
        name: "Ternary Bonsai 8B (On This Device)",
        repository: "prism-ml/Ternary-Bonsai-8B-mlx-2bit",
        revision: "9260b24298e4211e804663e9f519962cf59f34be",
        downloadBytes: 2_300_000_000,
        memoryGateBytes: 16 * 1_073_741_824,
        contextTokens: 65_536,
        licenceIdentifier: "Apache-2.0",
        licenceURL: "https://huggingface.co/prism-ml/Ternary-Bonsai-8B-mlx-2bit",
        disablesThinkingViaTemplate: false
    )

    /// Display order: smaller/broadly-available model first, matching `AIProviderCatalog`'s
    /// picker ordering (Apple On-Device, then these, then LM Studio, then everything else).
    static let all: [LocalModelDescriptor] = [qwen35_2b, ternaryBonsai8b]

    static func descriptor(for key: String) -> LocalModelDescriptor? {
        all.first { $0.key == key }
    }
}
