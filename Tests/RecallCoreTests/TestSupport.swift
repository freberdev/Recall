import Foundation
@testable import RecallCore

/// A temporary directory that is removed when the value is deallocated.
final class TempDirectory {
    let url: URL

    init() {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("recall-tests-\(UUID().uuidString)", isDirectory: true)
    }

    deinit {
        // Restore permissions first so a directory made read-only by a test can be removed.
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: history.path)
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        try? FileManager.default.removeItem(at: url)
    }

    var history: URL { url.appendingPathComponent("History", isDirectory: true) }

    func fileNames() -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: history.path)) ?? []).sorted()
    }

    func files(key: Data = testKey) -> ClipFiles {
        ClipFiles(directory: history, cipher: ClipCipher(keyData: key))
    }
}

/// A fixed key, so that tests can write files with one value and read them with another.
let testKey = Data(repeating: 7, count: ClipCipher.keyLength)
let otherKey = Data(repeating: 9, count: ClipCipher.keyLength)

func date(_ seconds: TimeInterval) -> Date {
    Date(timeIntervalSince1970: 1_800_000_000 + seconds)
}

func makeClip(_ text: String, at seconds: TimeInterval = 0, id: UUID = UUID()) -> Clip {
    Clip(id: id, kind: .of(text), text: text, created: date(seconds), used: date(seconds))
}
