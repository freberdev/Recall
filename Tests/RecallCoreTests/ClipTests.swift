import Foundation
import Testing
@testable import RecallCore

@Suite struct ClipKindTests {
    @Test(arguments: [
        "https://example.com",
        "http://example.com/path?query=1#fragment",
        "  https://example.com/with-space-around \n",
        "ftp://files.example.com/readme.txt",
        "ssh://git@example.com/repo.git",
        "file:///Users/someone/notes.txt",
        "mailto:someone@example.com",
        "obsidian://open?vault=Notes",
        "https://sv.wikipedia.org/wiki/Räksmörgås",
    ])
    func addressesAreLinks(_ text: String) {
        #expect(Clip.Kind.of(text) == .link)
    }

    @Test(arguments: [
        "",
        "   ",
        "just some words",
        "see https://example.com for more",
        "https://example.com\nhttps://example.org",
        "std::vector",
        "localhost:3000",
        "C:\\Users\\someone",
        "key: value",
        "https://",
        "mailto:",
        "example.com",
        "12:30",
    ])
    func everythingElseIsText(_ text: String) {
        #expect(Clip.Kind.of(text) == .text)
    }

    @Test func aVeryLongAddressIsText() {
        let long = "https://example.com/" + String(repeating: "a", count: 3000)
        #expect(Clip.Kind.of(long) == .text)
    }

    @Test func aNewClipIsCreatedAndUsedAtTheSameTime() {
        let clip = Clip(text: "https://example.com", now: date(5))
        #expect(clip.kind == .link)
        #expect(clip.created == date(5))
        #expect(clip.used == date(5))
    }
}

@Suite struct ClipCipherTests {
    let context = Data("RCL1".utf8)

    @Test func whatIsSealedCanBeOpened() throws {
        let cipher = try #require(ClipCipher(keyData: testKey))
        let secret = Data("räksmörgås 🦐".utf8)
        let sealed = try cipher.seal(secret, context: context)
        #expect(try cipher.open(sealed, context: context) == secret)
    }

    @Test func theSealedDataDoesNotContainThePlainText() throws {
        let cipher = try #require(ClipCipher(keyData: testKey))
        let secret = Data("a recognisable phrase".utf8)
        let sealed = try cipher.seal(secret, context: context)
        #expect(sealed.range(of: secret) == nil)
        #expect(sealed.count == secret.count + 28) // nonce and tag
    }

    @Test func sealingTwiceGivesDifferentData() throws {
        let cipher = try #require(ClipCipher(keyData: testKey))
        let secret = Data("same text".utf8)
        #expect(try cipher.seal(secret, context: context) != cipher.seal(secret, context: context))
    }

    @Test func anotherKeyCannotOpenIt() throws {
        let sealed = try #require(ClipCipher(keyData: testKey)).seal(Data("secret".utf8), context: context)
        let other = try #require(ClipCipher(keyData: otherKey))
        #expect(throws: (any Error).self) { try other.open(sealed, context: context) }
    }

    @Test func changedDataDoesNotOpen() throws {
        let cipher = try #require(ClipCipher(keyData: testKey))
        var sealed = try cipher.seal(Data("secret".utf8), context: context)
        sealed[sealed.count / 2] ^= 0x01
        #expect(throws: (any Error).self) { try cipher.open(sealed, context: context) }
    }

    @Test func anotherContextDoesNotOpen() throws {
        let cipher = try #require(ClipCipher(keyData: testKey))
        let sealed = try cipher.seal(Data("secret".utf8), context: context)
        #expect(throws: (any Error).self) { try cipher.open(sealed, context: Data("RCL2".utf8)) }
    }

    @Test func tooShortDataDoesNotOpen() throws {
        let cipher = try #require(ClipCipher(keyData: testKey))
        #expect(throws: (any Error).self) { try cipher.open(Data([1, 2, 3]), context: context) }
    }

    @Test func aKeyMustBeThirtyTwoBytes() {
        #expect(ClipCipher(keyData: Data(repeating: 1, count: 16)) == nil)
        #expect(ClipCipher(keyData: Data()) == nil)
        #expect(ClipCipher(keyData: Data(repeating: 1, count: 32)) != nil)
    }

    @Test func newKeysAreThirtyTwoBytesAndDiffer() {
        let first = ClipCipher.makeKeyData(), second = ClipCipher.makeKeyData()
        #expect(first.count == 32)
        #expect(first != second)
    }
}
