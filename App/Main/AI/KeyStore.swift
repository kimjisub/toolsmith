import Foundation
import Security
import ToolsmithKit

/// Where the OpenRouter key lives: this Mac's keychain, under the app's own service name (its bundle id).
enum KeyStore {
    private static let service = AppIdentity.bundleID
    private static let account = "openrouter-api-key"

    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }

    static var savedKey: String? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary, &result) == errSecSuccess, let data = result as? Data,
              let key = String(data: data, encoding: .utf8), !key.isEmpty else { return nil }
        return key
    }

    /// The key to use, if there is one. Only the keychain holds it: a key built into the app would be
    /// readable by anyone with a copy. Reading it may make macOS ask the user to allow it (when the
    /// item was saved by a differently signed build), so this is only called at the moment of asking the AI.
    static var key: String? { savedKey }

    /// Whether a key is saved in the keychain, without reading it. Asking for the item's attributes
    /// alone never raises the keychain's permission dialog, so this is safe to call while drawing.
    static var hasSavedKey: Bool {
        var request = query
        request[kSecReturnAttributes as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        return SecItemCopyMatching(request as CFDictionary, &result) == errSecSuccess
    }

    /// Whether there is a key to use, without reading it.
    static var isAvailable: Bool { hasSavedKey }

    @discardableResult static func save(_ key: String) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        SecItemDelete(query as CFDictionary)
        var item = query
        item[kSecValueData as String] = Data(trimmed.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    static func delete() {
        SecItemDelete(query as CFDictionary)
    }
}
