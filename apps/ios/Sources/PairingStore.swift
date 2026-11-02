import Foundation
import Security

/// Pairing is a secret, separate from app preferences. No iCloud synchronization.
struct PairingStore {
    var account = "receiver-v1"
    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "covoo.pairing",
         kSecAttrAccount as String: account,
         kSecAttrSynchronizable as String: false]
    }

    func load() throws -> String? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data,
              let link = String(data: data, encoding: .utf8) else {
            throw WireFailure.invalid("Saved pairing unavailable (Keychain \(status)). Unlock the phone or scan again.")
        }
        _ = try PairingDetails(link: link)
        return link
    }

    func save(_ link: String) throws {
        _ = try PairingDetails(link: link)
        let attributes: [String: Any] = [
            kSecValueData as String: Data(link.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            let item = query.merging(attributes) { _, value in value }
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else {
                throw WireFailure.invalid("Could not remember pairing in Keychain.")
            }
        } else if status != errSecSuccess {
            throw WireFailure.invalid("Could not update saved pairing (Keychain \(status)).")
        }
    }

    func forget() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw WireFailure.invalid("Could not forget pairing (Keychain \(status)).")
        }
    }
}
