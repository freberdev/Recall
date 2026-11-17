import Foundation
import RecallCore
import Security

/// The key that encrypts the history, kept in the user's login keychain.
enum Keychain {
    struct Failure: Error {
        let status: OSStatus
    }

    private static let service = Bundle.main.bundleIdentifier ?? "com.freberdev.recall"

    /// The stored key, or a new one if none has been stored yet.
    ///
    /// Throws when the keychain cannot be reached or holds something that is not a key.
    /// An existing key is never replaced: without it the history on disk cannot be read.
    static func historyKey(account: String) throws -> Data {
        if let existing = try read(account: account) {
            guard existing.count == ClipCipher.keyLength else { throw Failure(status: errSecDecode) }
            return existing
        }
        let key = ClipCipher.makeKeyData()
        let attributes: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecAttrLabel: "Recall",
            kSecValueData: key,
        ]
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else { throw Failure(status: status) }
        return key
    }

    private static func read(account: String) throws -> Data? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess: return result as? Data
        case errSecItemNotFound: return nil
        default: throw Failure(status: status)
        }
    }
}
