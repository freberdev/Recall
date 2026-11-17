import Foundation

/// The system clipboard, as far as the watcher needs it.
@MainActor
public protocol ClipboardSource: AnyObject {
    /// A number that grows every time the contents change.
    var changeCount: Int { get }
    /// The kinds of data on the clipboard. Asking for them does not read the content.
    var types: [String] { get }
    /// The content as plain text.
    func readString() -> String?
}

/// Notices when the clipboard changes and records the new text in the history.
///
/// macOS has no notification for clipboard changes, so `poll()` is called on a timer. It only
/// compares a number, and reads the clipboard at most once per change.
@MainActor
public final class ClipboardWatcher {
    /// While paused, changes are noted but nothing is read or recorded.
    ///
    /// Whatever is on the clipboard at the moment of pausing or resuming is left alone, also
    /// when it was copied so recently that no poll has seen it yet.
    public var isPaused: Bool {
        didSet {
            guard isPaused != oldValue else { return }
            lastChangeCount = source.changeCount
        }
    }

    private let source: ClipboardSource
    private let store: HistoryStore
    private let now: () -> Date
    private var lastChangeCount: Int?

    public init(
        source: ClipboardSource, store: HistoryStore, isPaused: Bool = false,
        now: @escaping () -> Date = Date.init
    ) {
        self.source = source
        self.store = store
        self.isPaused = isPaused
        self.now = now
    }

    /// Starts from the clipboard as it is now. What was copied before Recall was running is not collected.
    public func start() {
        lastChangeCount = source.changeCount
    }

    public func poll() {
        let count = source.changeCount
        guard count != lastChangeCount else { return }
        lastChangeCount = count

        guard !isPaused, CaptureRule.allowsReading(types: source.types) else { return }
        let string = source.readString()
        // Another app may have replaced the contents, or marked them as confidential, between
        // the check and the read. What was read is then thrown away, and a replacement is
        // judged on its own at the next poll.
        guard source.changeCount == count, CaptureRule.allowsReading(types: source.types),
              let text = CaptureRule.text(from: string)
        else { return }
        store.record(text, now: now())
    }

    /// Tells the watcher that the change with this number was made by Recall itself.
    public func ignoreChange(_ changeCount: Int) {
        lastChangeCount = changeCount
    }
}
