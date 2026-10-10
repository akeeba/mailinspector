//
//  Mail Inspector
//
//  Copyright (c) 2026 Nicholas K. Dionysopoulos / Akeeba Ltd
//  Licensed under the MIT License. See license.txt in the project root for details.
//

import Testing
import Foundation
@testable import Mail_Inspector

/// Tests for `InspectorSettings`'s silent system-prompt migration: a stored `aiSystemPrompt`
/// that still exactly matches a previously-shipped `MessageInsightsSession.defaultInstructions`
/// is replaced with the current default on launch, without asking — but a prompt the user has
/// actually edited, even slightly, is left alone.
@MainActor
@Suite("InspectorSettings system-prompt migration")
struct InspectorSettingsTests {
    /// Mirrors `InspectorSettings`'s own private `aiSystemPromptKey` — there's no accessor for
    /// it, and this is the one UserDefaults key these tests need to seed directly.
    private static let key = "aiSystemPrompt"

    private func withStoredPrompt(_ value: String?, _ body: () -> Void) {
        let defaults = UserDefaults.standard
        let original = defaults.string(forKey: Self.key)
        if let value {
            defaults.set(value, forKey: Self.key)
        } else {
            defaults.removeObject(forKey: Self.key)
        }
        body()
        if let original {
            defaults.set(original, forKey: Self.key)
        } else {
            defaults.removeObject(forKey: Self.key)
        }
    }

    @Test("Upgrades a stored prompt that still exactly matches a previous default")
    func upgradesLegacyDefault() {
        guard let legacyPrompt = MessageInsightsSession.legacyDefaultInstructions.first else {
            Issue.record("No legacy prompt recorded to test against")
            return
        }
        withStoredPrompt(legacyPrompt) {
            let settings = InspectorSettings()
            #expect(settings.aiSystemPrompt == MessageInsightsSession.defaultInstructions)
        }
    }

    @Test("Leaves a user-edited prompt untouched, even if it only slightly differs from a legacy default")
    func leavesCustomPromptAlone() {
        let customPrompt = "This is my own, hand-edited system prompt."
        withStoredPrompt(customPrompt) {
            let settings = InspectorSettings()
            #expect(settings.aiSystemPrompt == customPrompt)
        }
    }

    @Test("Falls back to the current default when nothing is stored yet")
    func fallsBackToCurrentDefaultWhenUnset() {
        withStoredPrompt(nil) {
            let settings = InspectorSettings()
            #expect(settings.aiSystemPrompt == MessageInsightsSession.defaultInstructions)
        }
    }
}
