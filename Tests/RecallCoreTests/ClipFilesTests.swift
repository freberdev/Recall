import Foundation
import Testing
@testable import RecallCore

@Suite struct ClipFilesTests {
    let temp = TempDirectory()
    var files: ClipFiles { temp.files() }

    @Test func aClipComesBackAsItWasWritten() throws {
        let clip = Clip(
            id: UUID(), kind: .link, text: "https://example.com/räksmörgås?x=1 🦐\r\n\ttabbed",
            created: date(1.25), used: date(99.5))
        try files.write(clip)
        #expect(files.loadAll() == [clip])
    }

    @Test func theFileIsNamedAfterTheClip() throws {
        let clip = makeClip("hello")
        try files.write(clip)
        #expect(temp.fileNames() == ["\(clip.id.uuidString).clip"])
    }

    @Test func theTextIsNotReadableOnDisk() throws {
        let clip = makeClip("a recognisable phrase that must not be on disk")
        try files.write(clip)
        let raw = try Data(contentsOf: files.url(for: clip.id))
        #expect(raw.starts(with: Data("RCL1".utf8)))
        #expect(raw.range(of: Data("recognisable".utf8)) == nil)
        #expect(raw.range(of: Data(clip.id.uuidString.utf8)) == nil)
    }

    @Test func onlyTheUserCanReadTheFolderAndTheFiles() throws {
        let clip = makeClip("private")
        try files.write(clip)
        let folder = try FileManager.default.attributesOfItem(atPath: temp.history.path)
        let file = try FileManager.default.attributesOfItem(atPath: files.url(for: clip.id).path)
        #expect(folder[.posixPermissions] as? Int == 0o700)
        #expect(file[.posixPermissions] as? Int == 0o600)
    }

    @Test func writingAgainReplacesTheFile() throws {
        var clip = makeClip("first")
        try files.write(clip)
        clip.used = date(50)
        try files.write(clip)
        #expect(temp.fileNames().count == 1)
        #expect(files.loadAll() == [clip])
    }

    @Test func noTemporaryFileIsLeftAfterAWrite() throws {
        try files.write(makeClip("one"))
        let all = try FileManager.default.contentsOfDirectory(atPath: temp.history.path)
        #expect(all.allSatisfy { !$0.hasSuffix(".tmp") })
    }

    @Test func aMissingFolderIsEmptyAndIsCreatedOnWrite() throws {
        #expect(files.loadAll().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: temp.history.path))
        try files.write(makeClip("one"))
        #expect(files.loadAll().count == 1)
    }

    @Test func theFolderIsRecreatedIfItDisappears() throws {
        try files.write(makeClip("one"))
        try FileManager.default.removeItem(at: temp.history)
        try files.write(makeClip("two"))
        #expect(files.loadAll().map(\.text) == ["two"])
    }

    @Test func filesWrittenWithAnotherKeyAreSkippedAndLeftAlone() throws {
        try temp.files(key: otherKey).write(makeClip("old key"))
        let clip = makeClip("current key")
        try files.write(clip)
        #expect(files.loadAll() == [clip])
        #expect(temp.fileNames().count == 2)
    }

    @Test func foreignAndDamagedFilesAreSkippedAndLeftAlone() throws {
        let clip = makeClip("good")
        try files.write(clip)
        let folder = temp.history
        try Data("not a clip".utf8).write(to: folder.appendingPathComponent("\(UUID().uuidString).clip"))
        try Data("RCL1".utf8).write(to: folder.appendingPathComponent("\(UUID().uuidString).clip"))
        try Data().write(to: folder.appendingPathComponent("\(UUID().uuidString).clip"))
        try Data("x".utf8).write(to: folder.appendingPathComponent(".DS_Store"))
        try Data("x".utf8).write(to: folder.appendingPathComponent("notes.txt"))

        #expect(files.loadAll() == [clip])
        #expect(temp.fileNames().count == 6)
    }

    @Test func aCopiedFileUnderAnotherNameIsNotASecondClip() throws {
        let clip = makeClip("only once")
        try files.write(clip)
        try FileManager.default.copyItem(
            at: files.url(for: clip.id), to: temp.history.appendingPathComponent("\(UUID().uuidString).clip"))
        #expect(files.loadAll() == [clip])
    }

    @Test func aTruncatedFileIsSkipped() throws {
        let clip = makeClip(String(repeating: "long text ", count: 100))
        try files.write(clip)
        let url = files.url(for: clip.id)
        let raw = try Data(contentsOf: url)
        try raw.prefix(raw.count / 2).write(to: url)
        #expect(files.loadAll().isEmpty)
    }

    @Test func leftoverTemporaryFilesAreRemovedOnLoad() throws {
        try files.write(makeClip("one"))
        let leftover = temp.history.appendingPathComponent(".\(UUID().uuidString).clip.tmp")
        try Data("half".utf8).write(to: leftover)
        _ = files.loadAll()
        #expect(!FileManager.default.fileExists(atPath: leftover.path))
    }

    @Test func deleteRemovesTheFile() throws {
        let keep = makeClip("keep"), remove = makeClip("remove")
        try files.write(keep)
        try files.write(remove)
        try files.delete(id: remove.id)
        #expect(files.loadAll() == [keep])
    }

    @Test func deletingSomethingThatIsGoneIsNotAnError() throws {
        try files.delete(id: UUID())
        try files.write(makeClip("one"))
        try files.delete(id: UUID())
    }

    @Test func deleteAllRemovesEveryClipFileButNothingElse() throws {
        try files.write(makeClip("one"))
        try temp.files(key: otherKey).write(makeClip("unreadable"))
        try Data("x".utf8).write(to: temp.history.appendingPathComponent("notes.txt"))
        #expect(files.fileCount == 2)

        try files.deleteAll()

        #expect(temp.fileNames() == ["notes.txt"])
        #expect(files.fileCount == 0)
    }

    @Test func deleteAllOnAMissingFolderIsNotAnError() throws {
        try files.deleteAll()
    }

    @Test func withoutAKeyNothingIsReadOrWrittenButFilesCanBeRemoved() throws {
        try files.write(makeClip("one"))
        let locked = ClipFiles(directory: temp.history, cipher: nil)

        #expect(!locked.canWrite)
        #expect(locked.loadAll().isEmpty)
        #expect(throws: ClipFiles.Failure.noKey) { try locked.write(makeClip("two")) }
        #expect(locked.fileCount == 1)
        try locked.deleteAll()
        #expect(locked.fileCount == 0)
    }

    @Test func aWriteToAFolderThatCannotBeWrittenFails() throws {
        try files.write(makeClip("one"))
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: temp.history.path)
        #expect(throws: (any Error).self) { try files.write(makeClip("two")) }
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: temp.history.path)
        #expect(files.loadAll().map(\.text) == ["one"])
    }

    @Test func oddTextSurvives() throws {
        let texts = [
            String(repeating: "\n", count: 5) + "x",
            "line one\r\nline two\r\n",
            "👨‍👩‍👧‍👦 family, e\u{301} combining, \u{0000} null",
            String(repeating: "A megabyte of text. ", count: 50_000),
        ]
        for text in texts {
            let clip = makeClip(text)
            try files.write(clip)
            let loaded = files.loadAll().first { $0.id == clip.id }
            #expect(loaded?.text.unicodeScalars.elementsEqual(text.unicodeScalars) == true)
        }
    }
}
