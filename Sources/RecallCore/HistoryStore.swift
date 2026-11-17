import Foundation
import Observation

/// The history in memory, most recently used first, kept in step with the files on disk.
@MainActor @Observable
public final class HistoryStore {
    public private(set) var clips: [Clip] = [] {
        didSet { revision &+= 1 }
    }

    /// Grows every time `clips` changes, so that work based on the list can be reused until then.
    @ObservationIgnored public private(set) var revision = 0

    public private(set) var limits: Limits

    @ObservationIgnored private let files: ClipFiles
    /// Clips whose latest state is not on disk. They are written again at the next opportunity.
    private var unsaved: Set<UUID> = []
    /// True when a clip that should be gone could not be removed from disk. It stays in the list.
    private var removalFailed = false
    /// True when the last image could not be written. An image is too large to wait in memory
    /// for a later attempt, so it is not collected at all.
    private var imageWriteFailed = false

    public init(files: ClipFiles, limits: Limits = .default) {
        self.files = files
        self.limits = limits
    }

    public var directory: URL { files.directory }

    /// True while the list in memory and the files on disk do not agree: something could not
    /// be written or removed. The list is still right, but it may not survive a restart.
    public var saveFailed: Bool {
        !files.canWrite || !unsaved.isEmpty || removalFailed || imageWriteFailed
    }

    /// True when there is something for `deleteAll` to remove: clips in the list, or files
    /// on disk that could not be read, for instance after the key was lost.
    public var hasAnythingToClear: Bool {
        !clips.isEmpty || files.fileCount > 0
    }

    /// Reads the files and drops what the limits no longer allow.
    public func load(now: Date) {
        clips = files.loadAll().sorted(by: Self.isBefore)
        unsaved = []
        prune(now: now)
    }

    /// Adds what was just copied. Text that is already in the history moves to the top
    /// instead of appearing twice.
    @discardableResult
    public func record(_ text: String, now: Date) -> Clip {
        if let existing = clips.first(where: { $0.kind != .image && $0.text == text }) {
            return touch(existing, now: now)
        }
        var clip = Clip(text: text, now: now)
        clip.used = stamp(now)
        clips.insert(clip, at: 0)
        persist(clip)
        prune(now: now)
        return clip
    }

    /// Adds an image that was just copied. The same image copied again moves to the top.
    /// Nil if images are not collected, or if the image could not be written to disk.
    @discardableResult
    public func record(image: CapturedImage, now: Date) -> Clip? {
        guard limits.collectsImages else { return nil }
        if let existing = clips.first(where: { $0.image?.digest == image.info.digest }) {
            return touch(existing, now: now)
        }
        var clip = Clip(image: image.info, now: now)
        do {
            try files.writeImage(image.data, id: clip.id)
            imageWriteFailed = false
        } catch {
            imageWriteFailed = true
            return nil
        }
        clip.used = stamp(now)
        clips.insert(clip, at: 0)
        persist(clip)
        prune(now: now)
        return clip
    }

    /// The stored image of a clip, read from disk.
    public func imageData(for id: UUID) -> Data? {
        files.readImage(id: id)
    }

    /// Moves a clip to the top, as when it is put back on the clipboard.
    public func markUsed(id: UUID, now: Date) {
        guard let clip = clips.first(where: { $0.id == id }) else { return }
        touch(clip, now: now)
    }

    public func delete(id: UUID) throws {
        try files.delete(id: id)
        clips.removeAll { $0.id == id }
        unsaved.remove(id)
    }

    /// Removes everything, including files that could not be read. If some files cannot be
    /// removed, the list is left showing what is still on disk.
    public func deleteAll() throws {
        do {
            try files.deleteAll()
        } catch {
            clips = files.loadAll().sorted(by: Self.isBefore)
            unsaved = []
            throw error
        }
        clips = []
        unsaved = []
        removalFailed = false
        imageWriteFailed = false
    }

    public func setLimits(_ new: Limits, now: Date) {
        limits = new
        prune(now: now)
    }

    /// Removes clips that are too old, then the least recently used beyond the largest count.
    /// Images are counted apart from texts and links, each against its own limit.
    /// A clip whose file cannot be removed stays in the list and is tried again next time.
    public func prune(now: Date) {
        saveUnsaved()

        var doomed: [Clip] = []
        if let maxAge = limits.maxAge {
            doomed += clips.filter { now.timeIntervalSince($0.used) > maxAge }
        }
        let expired = Set(doomed.map(\.id))
        let kept = clips.filter { !expired.contains($0.id) }
        doomed += kept.filter { $0.kind != .image }.dropFirst(max(limits.maxCount, 0))
        doomed += kept.filter { $0.kind == .image }.dropFirst(max(limits.maxImageCount, 0))

        var removed: Set<UUID> = []
        for clip in doomed {
            if (try? files.delete(id: clip.id)) != nil { removed.insert(clip.id) }
        }
        let failed = removed.count < doomed.count
        if failed != removalFailed { removalFailed = failed }
        guard !removed.isEmpty else { return }
        clips.removeAll { removed.contains($0.id) }
        unsaved.subtract(removed)
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

    // MARK: Writing

    private func persist(_ clip: Clip) {
        unsaved.insert(clip.id)
        saveUnsaved()
    }

    /// Writes every clip that is not on disk yet. One successful write must not hide that
    /// earlier ones failed, so each clip stays marked until its own file is written.
    private func saveUnsaved() {
        guard files.canWrite, !unsaved.isEmpty else { return }
        var remaining: Set<UUID> = []
        for clip in clips where unsaved.contains(clip.id) {
            if (try? files.write(clip)) == nil { remaining.insert(clip.id) }
        }
        unsaved = remaining
    }

    /// Most recently used first. Ties are settled the same way every time.
    static func isBefore(_ a: Clip, _ b: Clip) -> Bool {
        if a.used != b.used { return a.used > b.used }
        if a.created != b.created { return a.created > b.created }
        return a.id.uuidString < b.id.uuidString
    }
}
