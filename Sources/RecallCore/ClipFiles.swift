import Foundation

/// The history on disk: one encrypted file per clip.
///
/// A file is the four bytes `RCL1` followed by the sealed JSON of the clip. Each write goes to
/// a temporary file that then takes the place of the old one, so a crash can never leave half
/// a file behind, and a damaged file costs one clip rather than the whole history.
public struct ClipFiles {
    public enum Failure: Error, Equatable {
        /// There is no key to encrypt with, so nothing can be written.
        case noKey
        case couldNotWrite
    }

    static let fileExtension = "clip"
    static let header = Data("RCL1".utf8)

    public let directory: URL
    private let cipher: ClipCipher?
    private let fileManager = FileManager.default

    /// Without a cipher nothing can be read or written, but files can still be removed.
    public init(directory: URL, cipher: ClipCipher?) {
        self.directory = directory
        self.cipher = cipher
    }

    /// `~/Library/Application Support/Recall/History`, inside the app's container when sandboxed.
    public static var defaultDirectory: URL {
        URL.applicationSupportDirectory
            .appendingPathComponent("Recall", isDirectory: true)
            .appendingPathComponent("History", isDirectory: true)
    }

    public var canWrite: Bool { cipher != nil }

    // MARK: Reading

    /// Every clip that can be read. Files that cannot be opened are skipped and left alone.
    public func loadAll() -> [Clip] {
        guard let cipher else { return [] }
        removeLeftovers()
        return clipFiles().compactMap { url in
            guard let data = try? Data(contentsOf: url), data.starts(with: Self.header),
                  let json = try? cipher.open(data.dropFirst(Self.header.count), context: Self.header),
                  let stored = try? JSONDecoder().decode(StoredClip.self, from: json),
                  // The name of the file is the id. A copy under another name is not a second clip.
                  url.deletingPathExtension().lastPathComponent == stored.id.uuidString
            else { return nil }
            return stored.clip
        }
    }

    // MARK: Writing

    public func write(_ clip: Clip) throws {
        guard let cipher else { throw Failure.noKey }
        let json = try JSONEncoder().encode(StoredClip(clip))
        let data = try Self.header + cipher.seal(json, context: Self.header)

        try fileManager.createDirectory(
            at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let destination = url(for: clip.id)
        let temporary = directory.appendingPathComponent(".\(clip.id.uuidString).\(Self.fileExtension).tmp")
        guard fileManager.createFile(
            atPath: temporary.path, contents: data, attributes: [.posixPermissions: 0o600])
        else { throw Failure.couldNotWrite }
        guard rename(temporary.path, destination.path) == 0 else {
            try? fileManager.removeItem(at: temporary)
            throw Failure.couldNotWrite
        }
    }

    /// Removes the file for a clip. A file that is already gone is not an error.
    public func delete(id: UUID) throws {
        do {
            try fileManager.removeItem(at: url(for: id))
        } catch CocoaError.fileNoSuchFile {
            return
        }
    }

    /// Removes every clip file, also those that cannot be opened with the current key.
    /// Other files in the folder are left alone.
    public func deleteAll() throws {
        removeLeftovers()
        var firstError: Error?
        for url in clipFiles() {
            do {
                try fileManager.removeItem(at: url)
            } catch CocoaError.fileNoSuchFile {
                continue
            } catch {
                firstError = firstError ?? error
            }
        }
        if let firstError { throw firstError }
    }

    /// The number of clip files in the folder, readable or not.
    public var fileCount: Int { clipFiles().count }

    // MARK: Files

    func url(for id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).\(Self.fileExtension)")
    }

    private func clipFiles() -> [URL] {
        let contents = (try? fileManager.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        return contents.filter { $0.pathExtension == Self.fileExtension }
    }

    /// A temporary file is left behind only if a write was interrupted. Nothing refers to it.
    private func removeLeftovers() {
        let contents = (try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        for url in contents where url.lastPathComponent.hasPrefix(".")
            && url.lastPathComponent.hasSuffix(".\(Self.fileExtension).tmp") {
            try? fileManager.removeItem(at: url)
        }
    }
}

/// A clip as it is written inside the encrypted file.
private struct StoredClip: Codable {
    var version = 1
    var id: UUID
    var kind: Clip.Kind
    var text: String
    var created: Date
    var used: Date

    init(_ clip: Clip) {
        id = clip.id
        kind = clip.kind
        text = clip.text
        created = clip.created
        used = clip.used
    }

    var clip: Clip {
        Clip(id: id, kind: kind, text: text, created: created, used: used)
    }
}
