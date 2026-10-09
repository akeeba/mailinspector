//
//  Mail Inspector
//
//  Copyright (c) 2026 Nicholas K. Dionysopoulos / Akeeba Ltd
//  Licensed under the MIT License. See license.txt in the project root for details.
//

import Testing
import Foundation
@testable import Mail_Inspector

/// Tests for `AIProviderCatalog`: every entry has a unique key, Disabled sorts first, LM Studio
/// sorts right after it and is marked recommended, On-Device has no network surface, and lookup
/// by key works.
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

    @Test("LM Studio is second in the list and marked recommended")
    func lmStudioIsSecondAndRecommended() throws {
        #expect(AIProviderCatalog.all.dropFirst().first?.key == "lmstudio")
        #expect(AIProviderCatalog.all.dropFirst().first?.isRecommended == true)
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
