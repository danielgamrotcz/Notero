import Foundation
import Security

enum KeychainManager {
    private static let service = "cz.danielgamrot.Notero"

    static func save(key: String, value: String) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else {
            throw KeychainError.saveFailed(-1)
        }

        // Delete any existing item first
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked,
        ]

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        if status != errSecSuccess {
            // Fallback: store in UserDefaults (base64 encoded)
            Log.general.warning("Keychain save failed (\(status)), using UserDefaults fallback")
            UserDefaults.standard.set(data.base64EncodedString(), forKey: "fallback_\(key)")
            return
        }
        // Clear any fallback if Keychain save succeeded
        UserDefaults.standard.removeObject(forKey: "fallback_\(key)")
    }

    static func load(key: String) -> String? {
        // Try Keychain first
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: kCFBooleanTrue!,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecSuccess, let data = result as? Data,
           let value = String(data: data, encoding: .utf8),
           !value.isEmpty {
            return value
        }

        // Also try without accessibility attribute (for items saved before this fix)
        let legacyQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: kCFBooleanTrue!,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var legacyResult: AnyObject?
        let legacyStatus = SecItemCopyMatching(legacyQuery as CFDictionary, &legacyResult)

        if legacyStatus == errSecSuccess, let data = legacyResult as? Data,
           let value = String(data: data, encoding: .utf8),
           !value.isEmpty {
            return value
        }

        // Fallback: check UserDefaults
        if let encoded = UserDefaults.standard.string(forKey: "fallback_\(key)"),
           let data = Data(base64Encoded: encoded),
           let value = String(data: data, encoding: .utf8),
           !value.isEmpty {
            return value
        }

        Log.general.warning("Keychain load failed for \(key): status=\(status), legacyStatus=\(legacyStatus)")
        return nil
    }

    static func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
        UserDefaults.standard.removeObject(forKey: "fallback_\(key)")
    }

    static func hasKey(_ key: String) -> Bool {
        load(key: key) != nil
    }
}

enum KeychainError: LocalizedError {
    case saveFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .saveFailed(let status):
            return "Keychain save failed (status: \(status))"
        }
    }
}
