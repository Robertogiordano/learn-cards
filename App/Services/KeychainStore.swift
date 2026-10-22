import Foundation
import Security

/// Minimal generic-password wrapper; secrets never go to UserDefaults or backups.
enum KeychainStore {
    private static let service = "com.robertogiordano.learncards"

    private static func query(for account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    static func string(for account: String) -> String? {
        var lookup = query(for: account)
        lookup[kSecReturnData as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(lookup as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func set(_ value: String, for account: String) -> Bool {
        delete(account)
        guard !value.isEmpty else { return true }
        var attributes = query(for: account)
        attributes[kSecValueData as String] = Data(value.utf8)
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess
    }

    static func delete(_ account: String) {
        SecItemDelete(query(for: account) as CFDictionary)
    }
}

enum Secrets {
    static let openRouterAccount = "openrouter-api-key"

    static var openRouterKey: String? {
        guard let key = KeychainStore.string(for: openRouterAccount), !key.isEmpty else { return nil }
        return key
    }
}
