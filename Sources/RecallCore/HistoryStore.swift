import Foundation
import Observation

/// The history in memory, most recently used first, kept in step with the files on disk.
@MainActor @Observable
public final class HistoryStore {
    public private(set) var clips: [Clip] = []

    /// True when the last attempt to write or remove a file failed. The list in memory is
    /// still right, but it may not survive a restart.
    public private(set) var saveFailed = false

    public private(set) var limits: Limits

    @ObservationIgnored private let files: ClipFiles

    public init(files: ClipFiles, limits: Limits = .default) {
        self.files = files
        self.limits = limits
        saveFailed = !files.canWrite
    }

    public var directory: URL { files.directory }

    /// True when there is something for `deleteAll` to remove: clips in the list, or files
    /// on disk that could not be read, for instance after the key was lost.
    public var hasAnythingToClear: Bool {
        !clips.isEmpty || files.fileCount > 0
    }

    /// Reads the files and drops what the limits no longer allow.
    public func load(now: Date) {
        clips = files.loadAll().sorted(by: Self.isBefore)
        prune(now: now)
    }

    /// Adds what was just copied. Text that is already in the history moves to the top
    /// instead of appearing twice.
    @discardableResult
    public func record(_ text: String, now: Date) -> Clip {
        if let existing = clips.first(where: { $0.text == text }) {
            return touch(existing, now: now)
        }
        var clip = Clip(text: text, now: now)
        clip.used = stamp(now)
        clips.insert(clip, at: 0)
        persist(clip)
        prune(now: now)
        return clip
    }

    /// Moves a clip to the top, as when it is put back on the clipboard.
    public func markUsed(id: UUID, now: Date) {
        guard let clip = clips.first(where: { $0.id == id }) else { return }
        touch(clip, now: now)
    }

    public func delete(id: UUID) throws {
        try files.delete(id: id)
        clips.removeAll { $0.id == id }
    }

    /// Removes everything, including files that could not be read.
    public func deleteAll() throws {
        try files.deleteAll()
        clips = []
        saveFailed = !files.canWrite
    }

    public func setLimits(_ new: Limits, now: Date) {
        limits = new
        prune(now: now)
    }

    /// Removes clips that are too old, then the least recently used beyond the largest count.
    public func prune(now: Date) {
        var doomed: [Clip] = []
        if let maxAge = limits.maxAge {
            doomed += clips.filter { now.timeIntervalSince($0.used) > maxAge }
        }
        let kept = clips.filter { clip in !doomed.contains { $0.id == clip.id } }
        doomed += kept.dropFirst(max(limits.maxCount, 0))
        guard !doomed.isEmpty else { return }

        for clip in doomed {
            do { try files.delete(id: clip.id) } catch { saveFailed = true }
        }
        let ids = Set(doomed.map(\.id))
        clips.removeAll { ids.contains($0.id) }
    }

    // MARK: Order

    @discardableResult
    private func touch(_ clip: Clip, now: Date) -> Clip {
        var clip = clip
        clips.removeAll { $0.id == clip.id }
        clip.used = stamp(now)
        clips.insert(clip, at: 0)
        persist(clip)
        return clip
    }

    /// The time to give the clip that goes on top. Normally `now`, but never earlier than the
    /// clip it goes above, so the order holds after a restart even if the clock was set back.
    private func stamp(_ now: Date) -> Date {
        guard let top = clips.first else { return now }
        return max(now, top.used.addingTimeInterval(0.001))
    }

    private func persist(_ clip: Clip) {
        do {
            try files.write(clip)
            saveFailed = false
        } catch {
            saveFailed = true
        }
    }

    /// Most recently used first. Ties are settled the same way every time.
    static func isBefore(_ a: Clip, _ b: Clip) -> Bool {
        if a.used != b.used { return a.used > b.used }
        if a.created != b.created { return a.created > b.created }
        return a.id.uuidString < b.id.uuidString
    }
}
