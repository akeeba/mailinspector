//
//  Mail Inspector
//
//  Copyright (c) 2026 Nicholas K. Dionysopoulos / Akeeba Ltd
//  Licensed under the MIT License. See license.txt in the project root for details.
//

import Foundation
import Security

/// Stores each configured AI provider's API key in the macOS Keychain — never in `UserDefaults`
/// alongside the rest of `InspectorSettings`, and never read back into the Settings UI once
/// saved (a blank field always means "keep the existing key," never "there is no key").
///
/// A sandboxed app doesn't need any extra entitlement to use the Keychain for its own items, so
/// this is a thin, stateless wrapper around `Security.framework`'s `SecItem*` calls — no row
/// coordinator or database needed, since each provider only ever has one active key (see
/// `InspectorSettings.aiActiveProviderKey` — a single active configuration, not a saved list).
nonisolated enum AIKeychainStore {
    private static let service = "gr.dionysopoulos.mailinspector.ai-provider-keys"

    static func set(_ key: String, forProvider providerKey: String) {
        let data = Data(key.utf8)
        let query = matchQuery(providerKey: providerKey)

        if SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess {
            SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        } else {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            SecItemAdd(addQuery as CFDictionary, nil)
        }
    }

    static func get(forProvider providerKey: String) -> String? {
        var query = matchQuery(providerKey: providerKey)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    static func delete(forProvider providerKey: String) {
        SecItemDelete(matchQuery(providerKey: providerKey) as CFDictionary)
    }

    private static func matchQuery(providerKey: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: providerKey,
        ]
    }
}
