import Foundation
import Observation

/// The list in the panel: what is shown, which row is selected, and where keys go.
@MainActor @Observable
public final class HistoryList {
    /// Where keys go. The search field edits the query; the list acts on the selected clip.
    public enum Focus: Sendable { case search, list }

    /// Changing the query selects the first match and returns focus to the search field.
    public var query: String = "" {
        didSet {
            guard query != oldValue else { return }
            chosenID = nil
            focus = .search
        }
    }

    public var focus: Focus = .search

    private let store: HistoryStore
    private let locale: Locale
    /// The row the user moved to. Nil, or a clip that is no longer shown, means the first row.
    private var chosenID: UUID?
    /// The last search and what it gave. A view asks for the results many times per redraw.
    @ObservationIgnored private var lastSearch: (revision: Int, query: String, results: [Clip])?

    public init(store: HistoryStore, locale: Locale = .current) {
        self.store = store
        self.locale = locale
    }

    public var results: [Clip] {
        // Reading both registers them with observation even when the answer is already known.
        let clips = store.clips, query = query
        if let lastSearch, lastSearch.revision == store.revision, lastSearch.query == query {
            return lastSearch.results
        }
        let results = ClipSearch.filter(clips, query: query, locale: locale)
        lastSearch = (store.revision, query, results)
        return results
    }

    /// The selected clip. There is always one as long as anything is shown.
    public var selected: Clip? {
        let results = results
        return results.first { $0.id == chosenID } ?? results.first
    }

    public var selectedID: UUID? { selected?.id }

    /// Back to the state the panel opens in: no query, first row selected, focus in the search field.
    public func reset() {
        query = ""
        chosenID = nil
        focus = .search
    }

    public func select(_ id: UUID) {
        chosenID = id
        focus = .list
    }

    /// Moves the selection down (positive) or up (negative) and puts focus in the list.
    /// Up from the first row returns focus to the search field.
    public func moveSelection(by delta: Int) {
        let results = results
        guard !results.isEmpty, delta != 0 else { return }
        let index = results.firstIndex { $0.id == selectedID } ?? 0
        if delta < 0, index == 0 {
            focus = .search
            return
        }
        chosenID = results[min(max(index + delta, 0), results.count - 1)].id
        focus = .list
    }

    /// Deletes the selected clip and selects the row that takes its place.
    public func deleteSelected() throws {
        let before = results
        guard let clip = selected, let index = before.firstIndex(of: clip) else { return }
        try store.delete(id: clip.id)
        let remaining = results
        if remaining.isEmpty {
            chosenID = nil
            focus = .search
        } else {
            chosenID = remaining[min(index, remaining.count - 1)].id
        }
    }
}
