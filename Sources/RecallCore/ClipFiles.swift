import Foundation

/// The history on disk: one encrypted file per clip, and one more for an image.
///
/// A clip file is the four bytes `RCL1` followed by the sealed JSON of the clip. An image file
/// is `RCI1` followed by the sealed image. Each write goes to a temporary file that then takes
/// the place of the old one, so a crash can never leave half a file behind, and a damaged
/// file costs one clip rather than the whole history.
public struct ClipFiles {
    public enum Failure: Error, Equatable {
        /// There is no key to encrypt with, so nothing can be written.
        case noKey
        case couldNotWrite
    }

    static let fileExtension = "clip"
    static let header = Data("RCL1".utf8)
    static let imageExtension = "image"
    static let imageHeader = Data("RCI1".utf8)

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

    /// Every clip that can be read. Files that cannot be opened are skipped and left alone,
    /// and so is an image clip whose image is missing.
    public func loadAll() -> [Clip] {
        guard let cipher else { return [] }
        removeLeftovers()
        return files(withExtension: Self.fileExtension).compactMap { url in
            guard let json = open(url, header: Self.header, with: cipher),
                  let stored = try? JSONDecoder().decode(StoredClip.self, from: json),
                  // The name of the file is the id. A copy under another name is not a second clip.
                  url.deletingPathExtension().lastPathComponent == stored.id.uuidString
            else { return nil }
            let clip = stored.clip
            if clip.kind == .image {
                guard clip.image != nil, fileManager.fileExists(atPath: imageURL(for: clip.id).path)
                else { return nil }
            }
            return clip
        }
    }

    /// The stored image of a clip, or nil if it is missing or cannot be opened.
    public func readImage(id: UUID) -> Data? {
        guard let cipher else { return nil }
        return open(imageURL(for: id), header: Self.imageHeader, with: cipher)
    }

    private func open(_ url: URL, header: Data, with cipher: ClipCipher) -> Data? {
        guard let data = try? Data(contentsOf: url), data.starts(with: header) else { return nil }
        return try? cipher.open(data.dropFirst(header.count), context: header)
    }

    // MARK: Writing

    public func write(_ clip: Clip) throws {
        let json = try JSONEncoder().encode(StoredClip(clip))
        try seal(json, header: Self.header, to: url(for: clip.id))
    }

    /// Writes the image of a clip. It is written before the clip itself, so that a clip on
    /// disk always has its image.
    public func writeImage(_ data: Data, id: UUID) throws {
        try seal(data, header: Self.imageHeader, to: imageURL(for: id))
    }

    private func seal(_ plaintext: Data, header: Data, to destination: URL) throws {
        guard let cipher else { throw Failure.noKey }
        let data = try header + cipher.seal(plaintext, context: header)

        try fileManager.createDirectory(
            at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let temporary = directory.appendingPathComponent(".\(destination.lastPathComponent).tmp")
        guard fileManager.createFile(
            atPath: temporary.path, contents: data, attributes: [.posixPermissions: 0o600])
        else { throw Failure.couldNotWrite }
        guard rename(temporary.path, destination.path) == 0 else {
            try? fileManager.removeItem(at: temporary)
            throw Failure.couldNotWrite
        }
    }

    /// Removes the files for a clip. Files that are already gone are not an error.
    public func delete(id: UUID) throws {
        // The clip goes first: an image without a clip is tidied away at the next start,
        // while a clip without its image would be a row that cannot be used.
        try remove(url(for: id))
        try remove(imageURL(for: id))
    }

    /// Removes every clip and image file, also those that cannot be opened with the current key.
    /// Other files in the folder are left alone.
    public func deleteAll() throws {
        removeLeftovers()
        var firstError: Error?
        for url in files(withExtension: Self.fileExtension) + files(withExtension: Self.imageExtension) {
            do { try remove(url) } catch { firstError = firstError ?? error }
        }
        if let firstError { throw firstError }
    }

    /// The number of clip and image files in the folder, readable or not.
    public var fileCount: Int {
        files(withExtension: Self.fileExtension).count + files(withExtension: Self.imageExtension).count
    }

    // MARK: Files

    func url(for id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).\(Self.fileExtension)")
    }

    func imageURL(for id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).\(Self.imageExtension)")
    }

    private func remove(_ url: URL) throws {
        do {
            try fileManager.removeItem(at: url)
        } catch CocoaError.fileNoSuchFile {
            return
        }
    }

    private func files(withExtension pathExtension: String) -> [URL] {
        let contents = (try? fileManager.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        return contents.filter { $0.pathExtension == pathExtension }
    }

    /// Removes what an interrupted write or delete left behind: temporary files, and images
    /// whose clip is gone. Nothing refers to them.
    private func removeLeftovers() {
        let contents = (try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        for url in contents where url.lastPathComponent.hasPrefix(".") && url.pathExtension == "tmp" {
            let inner = url.deletingPathExtension().pathExtension
            if inner == Self.fileExtension || inner == Self.imageExtension {
                try? fileManager.removeItem(at: url)
            }
        }
        for url in files(withExtension: Self.imageExtension) {
            let clip = url.deletingPathExtension().appendingPathExtension(Self.fileExtension)
            if !fileManager.fileExists(atPath: clip.path) {
                try? fileManager.removeItem(at: url)
            }
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
    var image: Clip.ImageInfo?

    init(_ clip: Clip) {
        id = clip.id
        kind = clip.kind
        text = clip.text
        created = clip.created
        used = clip.used
        image = clip.image
    }

    var clip: Clip {
        Clip(id: id, kind: kind, text: text, created: created, used: used, image: image)
    }
}
