import Foundation
import Testing
@testable import RecallCore

@MainActor @Suite struct HistoryListTests {
    let temp = TempDirectory()
    let store: HistoryStore
    let list: HistoryList

    init() {
        store = HistoryStore(files: temp.files(), limits: Limits(maxCount: 100, maxAgeDays: nil))
        list = HistoryList(store: store, locale: Locale(identifier: "sv_SE"))
    }

    /// Records clips so that the first one named ends up on top.
    func fill(_ texts: String...) {
        for (offset, text) in texts.reversed().enumerated() {
            store.record(text, now: date(TimeInterval(offset)))
        }
    }

    @Test func theFirstRowIsSelectedFromTheStart() {
        fill("one", "two", "three")
        #expect(list.results.map(\.text) == ["one", "two", "three"])
        #expect(list.selected?.text == "one")
        #expect(list.focus == .search)
    }

    @Test func nothingIsSelectedInAnEmptyHistory() {
        #expect(list.selected == nil)
        #expect(list.selectedID == nil)
        list.moveSelection(by: 1)
        #expect(list.focus == .search)
    }

    @Test func downMovesToTheNextRowAndIntoTheList() {
        fill("one", "two", "three")
        list.moveSelection(by: 1)
        #expect(list.selected?.text == "two")
        #expect(list.focus == .list)
        list.moveSelection(by: 1)
        #expect(list.selected?.text == "three")
    }

    @Test func downStopsAtTheLastRow() {
        fill("one", "two")
        for _ in 0..<5 { list.moveSelection(by: 1) }
        #expect(list.selected?.text == "two")
    }

    @Test func upFromTheFirstRowReturnsToTheSearchField() {
        fill("one", "two")
        list.moveSelection(by: 1)
        list.moveSelection(by: -1)
        #expect(list.selected?.text == "one")
        #expect(list.focus == .list)
        list.moveSelection(by: -1)
        #expect(list.selected?.text == "one")
        #expect(list.focus == .search)
    }

    @Test func downWithASingleRowEntersTheList() {
        fill("only")
        list.moveSelection(by: 1)
        #expect(list.selected?.text == "only")
        #expect(list.focus == .list)
    }

    @Test func typingFiltersSelectsTheFirstMatchAndReturnsToTheSearchField() {
        fill("git status", "brew upgrade", "git rebase -i")
        list.moveSelection(by: 1)
        list.moveSelection(by: 1)

        list.query = "git"

        #expect(list.results.map(\.text) == ["git status", "git rebase -i"])
        #expect(list.selected?.text == "git status")
        #expect(list.focus == .search)
    }

    @Test func aQueryWithoutMatchesSelectsNothing() {
        fill("one", "two")
        list.query = "zebra"
        #expect(list.results.isEmpty)
        #expect(list.selected == nil)
    }

    @Test func resetClearsTheQueryAndGoesBackToTheTop() {
        fill("one", "two", "three")
        list.query = "t"
        list.moveSelection(by: 1)
        list.reset()
        #expect(list.query.isEmpty)
        #expect(list.selected?.text == "one")
        #expect(list.focus == .search)
    }

    @Test func resetWithoutAQueryStillGoesBackToTheTop() {
        fill("one", "two", "three")
        list.moveSelection(by: 2)
        list.reset()
        #expect(list.selected?.text == "one")
        #expect(list.focus == .search)
    }

    @Test func selectingARowPutsFocusInTheList() {
        fill("one", "two")
        list.select(store.clips[1].id)
        #expect(list.selected?.text == "two")
        #expect(list.focus == .list)
    }

    @Test func aNewCopyWhileTheListIsOpenKeepsTheChosenRow() {
        fill("one", "two")
        list.moveSelection(by: 1)
        store.record("zero", now: date(100))
        #expect(list.results.map(\.text) == ["zero", "one", "two"])
        #expect(list.selected?.text == "two")
    }

    @Test func ifTheChosenRowDisappearsTheFirstRowIsSelected() throws {
        fill("one", "two")
        list.moveSelection(by: 1)
        try store.delete(id: store.clips[1].id)
        #expect(list.selected?.text == "one")
    }

    @Test func theResultsFollowTheHistoryAndTheQuery() throws {
        fill("git status", "brew upgrade")
        #expect(list.results.map(\.text) == ["git status", "brew upgrade"])
        #expect(list.results.map(\.text) == ["git status", "brew upgrade"])

        list.query = "git"
        #expect(list.results.map(\.text) == ["git status"])

        store.record("git log", now: date(100))
        #expect(list.results.map(\.text) == ["git log", "git status"])

        try store.delete(id: store.clips[0].id)
        #expect(list.results.map(\.text) == ["git status"])

        store.markUsed(id: store.clips[1].id, now: date(200))
        list.query = ""
        #expect(list.results.map(\.text) == ["brew upgrade", "git status"])

        try store.deleteAll()
        #expect(list.results.isEmpty)
    }

    // MARK: Deleting

    @Test func deletingSelectsTheRowThatTakesItsPlace() throws {
        fill("one", "two", "three")
        list.moveSelection(by: 1)
        try list.deleteSelected()
        #expect(list.results.map(\.text) == ["one", "three"])
        #expect(list.selected?.text == "three")
        #expect(list.focus == .list)
    }

    @Test func deletingTheLastRowSelectsTheNewLastRow() throws {
        fill("one", "two", "three")
        list.moveSelection(by: 2)
        try list.deleteSelected()
        #expect(list.selected?.text == "two")
    }

    @Test func deletingTheOnlyRowReturnsToTheSearchField() throws {
        fill("only")
        list.moveSelection(by: 1)
        try list.deleteSelected()
        #expect(list.results.isEmpty)
        #expect(list.selected == nil)
        #expect(list.focus == .search)
    }

    @Test func deletingInAFilteredListStaysInTheFilteredList() throws {
        fill("git status", "brew upgrade", "git rebase", "git log")
        list.query = "git"
        list.moveSelection(by: 1)
        try list.deleteSelected()
        #expect(list.results.map(\.text) == ["git status", "git log"])
        #expect(list.selected?.text == "git log")
        #expect(store.clips.map(\.text) == ["git status", "brew upgrade", "git log"])
    }

    @Test func deletingWithNothingSelectedDoesNothing() throws {
        try list.deleteSelected()
        #expect(store.clips.isEmpty)
    }
}
