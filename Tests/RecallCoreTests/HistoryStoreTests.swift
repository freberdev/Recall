import Foundation
import Testing
@testable import RecallCore

@MainActor @Suite struct HistoryStoreTests {
    let temp = TempDirectory()

    func makeStore(limits: Limits = Limits(maxCount: 100, maxAgeDays: nil)) -> HistoryStore {
        HistoryStore(files: temp.files(), limits: limits)
    }

    /// A second store over the same folder, as after a restart of the app.
    func restarted(limits: Limits = Limits(maxCount: 100, maxAgeDays: nil), now: Date = date(1000)) -> HistoryStore {
        let store = makeStore(limits: limits)
        store.load(now: now)
        return store
    }

    // MARK: Recording

    @Test func whatIsCopiedIsRecordedOnceAndShownOnTop() {
        let store = makeStore()
        store.record("first", now: date(1))
        store.record("second", now: date(2))
        #expect(store.clips.map(\.text) == ["second", "first"])
        #expect(temp.fileNames().count == 2)
    }

    @Test func copyingTheSameTextAgainMovesItToTheTopInsteadOfAddingIt() {
        let store = makeStore()
        let first = store.record("alpha", now: date(1))
        store.record("beta", now: date(2))
        let again = store.record("alpha", now: date(3))

        #expect(store.clips.map(\.text) == ["alpha", "beta"])
        #expect(again.id == first.id)
        #expect(again.created == date(1))
        #expect(again.used == date(3))
        #expect(temp.fileNames().count == 2)
    }

    @Test func textThatDiffersOnlyInWhitespaceOrCaseIsKeptApart() {
        let store = makeStore()
        store.record("value", now: date(1))
        store.record("value ", now: date(2))
        store.record("Value", now: date(3))
        #expect(store.clips.count == 3)
    }

    @Test func linksAndTextAreToldApart() {
        let store = makeStore()
        #expect(store.record("https://example.com", now: date(1)).kind == .link)
        #expect(store.record("an ordinary sentence", now: date(2)).kind == .text)
    }

    // MARK: Surviving a restart

    @Test func theHistoryIsThereAfterARestartInTheSameOrder() {
        let store = makeStore()
        store.record("one", now: date(1))
        store.record("two", now: date(2))
        store.record("three", now: date(3))
        store.record("one", now: date(4))

        let later = restarted()
        #expect(later.clips == store.clips)
        #expect(later.clips.map(\.text) == ["one", "three", "two"])
    }

    @Test func markingAClipUsedMovesItToTheTopAndSurvivesARestart() {
        let store = makeStore()
        let old = store.record("old", now: date(1))
        store.record("new", now: date(2))

        store.markUsed(id: old.id, now: date(3))

        #expect(store.clips.map(\.text) == ["old", "new"])
        #expect(store.clips[0].created == date(1))
        #expect(restarted().clips.map(\.text) == ["old", "new"])
    }

    @Test func markingAnUnknownClipDoesNothing() {
        let store = makeStore()
        store.record("one", now: date(1))
        store.markUsed(id: UUID(), now: date(2))
        #expect(store.clips.map(\.text) == ["one"])
    }

    // MARK: Order

    @Test func theNewestGoesOnTopEvenIfTheClockWasSetBack() {
        let store = makeStore()
        store.record("before", now: date(1000))
        store.record("after the clock went back", now: date(10))

        #expect(store.clips.map(\.text) == ["after the clock went back", "before"])
        #expect(restarted(now: date(2000)).clips.map(\.text) == ["after the clock went back", "before"])
    }

    @Test func clipsRecordedAtTheSameInstantKeepTheirOrderAcrossRestarts() {
        let store = makeStore()
        for index in 0..<20 { store.record("clip \(index)", now: date(5)) }
        let expected = (0..<20).reversed().map { "clip \($0)" }

        #expect(store.clips.map(\.text) == expected)
        #expect(restarted().clips.map(\.text) == expected)
        #expect(restarted().clips.map(\.text) == expected)
    }

    @Test func identicalTimesOnDiskStillGiveAStableOrder() throws {
        let files = temp.files()
        for index in 0..<10 { try files.write(makeClip("clip \(index)", at: 0)) }
        let first = restarted().clips, second = restarted().clips
        #expect(first == second)
        #expect(first.count == 10)
    }

    // MARK: Deleting

    @Test func deletingRemovesTheClipFromTheListAndFromDisk() throws {
        let store = makeStore()
        let doomed = store.record("remove me", now: date(1))
        store.record("keep me", now: date(2))

        try store.delete(id: doomed.id)

        #expect(store.clips.map(\.text) == ["keep me"])
        #expect(restarted().clips.map(\.text) == ["keep me"])
    }

    @Test func clearingRemovesEverythingAlsoWhatCouldNotBeRead() throws {
        try temp.files(key: otherKey).write(makeClip("from an old key"))
        let store = makeStore()
        store.record("one", now: date(1))
        store.record("two", now: date(2))

        try store.deleteAll()

        #expect(store.clips.isEmpty)
        #expect(temp.fileNames().isEmpty)
    }

    @Test func filesThatCannotBeReadStillCountAsSomethingToClear() throws {
        let store = makeStore()
        #expect(!store.hasAnythingToClear)

        try temp.files(key: otherKey).write(makeClip("from an old key"))
        store.load(now: date(1))
        #expect(store.clips.isEmpty)
        #expect(store.hasAnythingToClear)

        try store.deleteAll()
        #expect(!store.hasAnythingToClear)
    }

    @Test func aHistoryWithClipsHasSomethingToClear() {
        let store = makeStore()
        store.record("one", now: date(1))
        #expect(store.hasAnythingToClear)
    }

    @Test func aDeletedTextCanBeCopiedAgain() throws {
        let store = makeStore()
        let first = store.record("again", now: date(1))
        try store.delete(id: first.id)
        let second = store.record("again", now: date(2))
        #expect(second.id != first.id)
        #expect(store.clips.map(\.text) == ["again"])
    }

    // MARK: Limits

    @Test func theLeastRecentlyUsedGoFirstWhenTheCountRunsOut() {
        let store = makeStore(limits: Limits(maxCount: 3, maxAgeDays: nil))
        for index in 1...5 { store.record("clip \(index)", now: date(TimeInterval(index))) }

        #expect(store.clips.map(\.text) == ["clip 5", "clip 4", "clip 3"])
        #expect(temp.fileNames().count == 3)
    }

    @Test func usingAnOldClipSavesItFromTheCountLimit() {
        let store = makeStore(limits: Limits(maxCount: 3, maxAgeDays: nil))
        let first = store.record("clip 1", now: date(1))
        store.record("clip 2", now: date(2))
        store.record("clip 3", now: date(3))
        store.markUsed(id: first.id, now: date(4))
        store.record("clip 4", now: date(5))

        #expect(store.clips.map(\.text) == ["clip 4", "clip 1", "clip 3"])
    }

    @Test func clipsUnusedForTooLongAreRemoved() {
        let day: TimeInterval = 86_400
        let store = makeStore(limits: Limits(maxCount: 100, maxAgeDays: 7))
        store.record("ancient", now: date(0))
        store.record("recent", now: date(6 * day))

        store.prune(now: date(7 * day + 1))

        #expect(store.clips.map(\.text) == ["recent"])
        #expect(temp.fileNames().count == 1)
    }

    @Test func aClipExactlyAtTheAgeLimitIsKept() {
        let store = makeStore(limits: Limits(maxCount: 100, maxAgeDays: 1))
        store.record("on the line", now: date(0))
        store.prune(now: date(86_400))
        #expect(store.clips.count == 1)
    }

    @Test func oldClipsAreRemovedWhenTheHistoryIsLoaded() {
        let store = makeStore()
        store.record("ancient", now: date(0))
        store.record("recent", now: date(86_400 * 40))

        let later = restarted(limits: Limits(maxCount: 100, maxAgeDays: 30), now: date(86_400 * 41))
        #expect(later.clips.map(\.text) == ["recent"])
        #expect(temp.fileNames().count == 1)
    }

    @Test func withoutAnAgeLimitNothingIsRemovedByAge() {
        let store = makeStore(limits: Limits(maxCount: 100, maxAgeDays: nil))
        store.record("ancient", now: date(0))
        store.prune(now: date(86_400 * 3650))
        #expect(store.clips.count == 1)
    }

    @Test func tighterLimitsApplyAtOnce() {
        let store = makeStore(limits: Limits(maxCount: 100, maxAgeDays: nil))
        for index in 1...10 { store.record("clip \(index)", now: date(TimeInterval(index))) }

        store.setLimits(Limits(maxCount: 4, maxAgeDays: nil), now: date(11))

        #expect(store.limits.maxCount == 4)
        #expect(store.clips.map(\.text) == ["clip 10", "clip 9", "clip 8", "clip 7"])
        #expect(temp.fileNames().count == 4)
    }

    // MARK: When the disk says no

    @Test func aClipThatCannotBeSavedStaysInTheListAndTheFailureShows() throws {
        let store = makeStore()
        store.record("saved", now: date(1))
        #expect(!store.saveFailed)

        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: temp.history.path)
        store.record("not saved", now: date(2))
        #expect(store.saveFailed)
        #expect(store.clips.map(\.text) == ["not saved", "saved"])

        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: temp.history.path)
        store.record("saved again", now: date(3))
        #expect(!store.saveFailed)
    }

    @Test func clipsThatCouldNotBeSavedAreSavedWhenTheDiskAllowsItAgain() throws {
        let store = makeStore()
        store.record("saved", now: date(1))
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: temp.history.path)
        store.record("failed one", now: date(2))
        store.record("failed two", now: date(3))
        #expect(restarted().clips.map(\.text) == ["saved"])

        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: temp.history.path)
        store.record("saved again", now: date(4))

        #expect(!store.saveFailed)
        #expect(restarted().clips.map(\.text) == ["saved again", "failed two", "failed one", "saved"])
    }

    @Test func clipsThatCouldNotBeSavedAreRetriedWhenTheHistoryIsPruned() throws {
        let store = makeStore()
        store.record("saved", now: date(1))
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: temp.history.path)
        store.record("failed", now: date(2))
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: temp.history.path)

        store.prune(now: date(3))

        #expect(!store.saveFailed)
        #expect(restarted().clips.map(\.text) == ["failed", "saved"])
    }

    @Test func oneFailureDoesNotHideAnother() throws {
        let store = makeStore()
        try FileManager.default.createDirectory(at: temp.history, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: temp.history.path)
        let failed = store.record("failed", now: date(1))
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: temp.history.path)
        #expect(store.saveFailed)

        // Deleting the clip that was never saved leaves nothing unsaved.
        try store.delete(id: failed.id)
        #expect(!store.saveFailed)
    }

    @Test func anExpiredClipThatCannotBeRemovedStaysUntilItCan() throws {
        let store = makeStore(limits: Limits(maxCount: 100, maxAgeDays: 1))
        store.record("ancient", now: date(0))
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: temp.history.path)

        store.prune(now: date(86_400 * 3))
        #expect(store.clips.map(\.text) == ["ancient"])
        #expect(store.saveFailed)

        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: temp.history.path)
        store.prune(now: date(86_400 * 3))
        #expect(store.clips.isEmpty)
        #expect(!store.saveFailed)
        #expect(temp.fileNames().isEmpty)
    }

    @Test func aClearThatOnlyPartlySucceedsLeavesTheListMatchingTheDisk() throws {
        let store = makeStore()
        store.record("goes", now: date(1))
        let stuck = store.record("stays", now: date(2))
        store.record("goes too", now: date(3))
        let stuckPath = temp.history.appendingPathComponent("\(stuck.id.uuidString).clip").path
        try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: stuckPath)
        defer { try? FileManager.default.setAttributes([.immutable: false], ofItemAtPath: stuckPath) }

        #expect(throws: (any Error).self) { try store.deleteAll() }

        #expect(store.clips.map(\.text) == ["stays"])
        #expect(temp.fileNames().count == 1)
    }

    @Test func aClipThatCannotBeDeletedStaysInTheList() throws {
        let store = makeStore()
        let clip = store.record("stubborn", now: date(1))
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: temp.history.path)

        #expect(throws: (any Error).self) { try store.delete(id: clip.id) }
        #expect(store.clips.map(\.text) == ["stubborn"])
    }

    @Test func withoutAKeyTheHistoryLivesOnlyInMemory() {
        let store = HistoryStore(files: ClipFiles(directory: temp.history, cipher: nil))
        #expect(store.saveFailed)
        store.record("only in memory", now: date(1))
        #expect(store.clips.map(\.text) == ["only in memory"])
        #expect(temp.fileNames().isEmpty)
    }
}
