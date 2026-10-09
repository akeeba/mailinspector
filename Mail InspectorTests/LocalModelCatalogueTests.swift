//
//  Mail Inspector
//
//  Copyright (c) 2026 Nicholas K. Dionysopoulos / Akeeba Ltd
//  Licensed under the MIT License. See license.txt in the project root for details.
//

import Testing
import Foundation
@testable import Mail_Inspector

/// Tests for `LocalModelCatalogue`/`LocalModelDescriptor`: catalogue data stays internally
/// consistent (unique keys, revisions that look like pinned commit SHAs, not branch names), and
/// `chatTemplateContext` matches each model's `disablesThinkingViaTemplate` flag.
///
/// Deliberately doesn't test `LocalModelSuitability.decision(for:)` against this test machine's
/// real hardware — that would make the suite's outcome depend on what Mac happens to run it. See
/// `LocalModelDecisionTests` for the hardware-independent part of that logic instead.
@Suite("LocalModelCatalogue")
struct LocalModelCatalogueTests {
    @Test("Every model has a unique key matching its AIProviderCatalog entry")
    func keysAreUniqueAndCatalogued() throws {
        let keys = LocalModelCatalogue.all.map(\.key)
        #expect(Set(keys).count == keys.count)
        for key in keys {
            #expect(AIProviderCatalog.definition(for: key)?.kind == .localMlx(modelKey: key))
        }
    }

    @Test("Revisions are pinned 40-character commit SHAs, not a branch name")
    func revisionsArePinned() throws {
        for descriptor in LocalModelCatalogue.all {
            #expect(descriptor.revision.count == 40)
            #expect(descriptor.revision.allSatisfy { $0.isHexDigit })
        }
    }

    @Test("Qwen 3.5 2B needs its chat template's thinking mode disabled")
    func qwenDisablesThinking() throws {
        let descriptor = LocalModelCatalogue.qwen35_2b
        #expect(descriptor.disablesThinkingViaTemplate)
        #expect(descriptor.chatTemplateContext?["enable_thinking"] as? Bool == false)
    }

    @Test("Ternary Bonsai 8B needs no chat-template override")
    func bonsaiNeedsNoOverride() throws {
        let descriptor = LocalModelCatalogue.ternaryBonsai8b
        #expect(descriptor.disablesThinkingViaTemplate == false)
        #expect(descriptor.chatTemplateContext == nil)
    }

    @Test("Looks up a descriptor by key")
    func looksUpByKey() throws {
        #expect(LocalModelCatalogue.descriptor(for: "mlx_qwen35_2b")?.repository == "mlx-community/Qwen3.5-2B-MLX-4bit")
        #expect(LocalModelCatalogue.descriptor(for: "does-not-exist") == nil)
    }
}

/// Tests for `LocalModelDecision.unavailableReason` — constructed directly with fixed byte
/// counts rather than going through `LocalModelSuitability.decision(for:)`, so these stay
/// deterministic regardless of which Mac runs the suite.
@Suite("LocalModelDecision")
struct LocalModelDecisionTests {
    @Test(".allowed has no unavailable reason")
    func allowedHasNoReason() throws {
        #expect(LocalModelDecision.allowed.unavailableReason == nil)
    }

    @Test("Unsupported hardware names Apple Silicon")
    func unsupportedHardwareMentionsAppleSilicon() throws {
        let reason = LocalModelDecision.unsupportedHardware.unavailableReason
        #expect(reason?.contains("Apple Silicon") == true)
    }

    @Test("Insufficient memory reports both figures")
    func insufficientMemoryReportsFigures() throws {
        let reason = LocalModelDecision.insufficientMemory(
            physicalBytes: 8 * 1_073_741_824,
            requiredBytes: 14 * 1_073_741_824
        ).unavailableReason
        #expect(reason != nil)
        #expect(reason?.contains("memory") == true)
    }

    @Test("Insufficient disk reports both figures")
    func insufficientDiskReportsFigures() throws {
        let reason = LocalModelDecision.insufficientDisk(
            needsBytes: 2_000_000_000,
            availableBytes: 500_000_000
        ).unavailableReason
        #expect(reason != nil)
        #expect(reason?.contains("disk space") == true)
    }
}
