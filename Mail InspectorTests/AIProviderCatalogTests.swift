//
//  Mail Inspector
//
//  Copyright (c) 2026 Nicholas K. Dionysopoulos / Akeeba Ltd
//  Licensed under the MIT License. See license.txt in the project root for details.
//

import Testing
import Foundation
@testable import Mail_Inspector

/// Tests for `AIProviderCatalog`: every entry has a unique key, the picker order is Disabled,
/// On-Device, the on-device MLX models, LM Studio, then everything else, On-Device has no
/// network surface, and lookup by key works.
@Suite("AIProviderCatalog")
struct AIProviderCatalogTests {
    @Test("Every provider has a unique key")
    func keysAreUnique() throws {
        let keys = AIProviderCatalog.all.map(\.key)
        #expect(Set(keys).count == keys.count)
    }

    @Test("Disabled is first in the list")
    func disabledIsFirst() throws {
        #expect(AIProviderCatalog.all.first?.key == "disabled")
        #expect(AIProviderCatalog.all.first?.kind == .disabled)
    }

    @Test("On-Device Apple Intelligence is second, before the on-device MLX models")
    func onDeviceIsSecond() throws {
        #expect(AIProviderCatalog.all.dropFirst().first?.key == "apple_ondevice")
    }

    @Test("Both on-device MLX models sort between On-Device and LM Studio, keyed by model")
    func localMlxModelsSortBetweenOnDeviceAndLMStudio() throws {
        let keys = AIProviderCatalog.all.map(\.key)
        guard let onDeviceIndex = keys.firstIndex(of: "apple_ondevice"),
              let lmStudioIndex = keys.firstIndex(of: "lmstudio") else {
            Issue.record("Expected both apple_ondevice and lmstudio to be present")
            return
        }
        let between = keys[(onDeviceIndex + 1)..<lmStudioIndex]
        #expect(Set(between) == Set(LocalModelCatalogue.all.map(\.key)))
        for key in between {
            #expect(AIProviderCatalog.definition(for: key)?.kind == .localMlx(modelKey: key))
        }
    }

    @Test("LM Studio is marked recommended")
    func lmStudioIsRecommended() throws {
        #expect(AIProviderCatalog.definition(for: "lmstudio")?.isRecommended == true)
    }

    @Test("On-Device Apple Intelligence has no endpoint, no editable endpoint, and no models path")
    func onDeviceHasNoNetworkSurface() throws {
        let onDevice = AIProviderCatalog.onDevice
        #expect(onDevice.kind == .onDevice)
        #expect(onDevice.defaultEndpoint.isEmpty)
        #expect(onDevice.isEndpointEditable == false)
        #expect(onDevice.modelsPath == nil)
    }

    @Test("Looks up a provider definition by its key")
    func looksUpByKey() throws {
        #expect(AIProviderCatalog.definition(for: "lmstudio")?.name == "LM Studio (Local)")
        #expect(AIProviderCatalog.definition(for: "does-not-exist") == nil)
    }
}
