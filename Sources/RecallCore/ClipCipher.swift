import CryptoKit
import Foundation

/// Encrypts what Recall writes to disk, with AES-256-GCM.
///
/// Every file gets its own random nonce, and the authentication tag makes a file that has been
/// changed, or that was written with another key, fail to open instead of yielding garbage.
public struct ClipCipher: Sendable {
    public static let keyLength = 32

    private let key: SymmetricKey

    /// Nil unless `keyData` is exactly 32 bytes.
    public init?(keyData: Data) {
        guard keyData.count == Self.keyLength else { return nil }
        key = SymmetricKey(data: keyData)
    }

    /// 32 random bytes for a new key.
    public static func makeKeyData() -> Data {
        SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
    }

    /// The nonce, the ciphertext and the tag in one piece. `context` is not stored, but the
    /// same value must be given to `open`.
    public func seal(_ plaintext: Data, context: Data) throws -> Data {
        let box = try AES.GCM.seal(plaintext, using: key, authenticating: context)
        guard let combined = box.combined else { throw CocoaError(.coderInvalidValue) }
        return combined
    }

    public func open(_ sealed: Data, context: Data) throws -> Data {
        try AES.GCM.open(AES.GCM.SealedBox(combined: sealed), using: key, authenticating: context)
    }
}
