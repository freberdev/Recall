import Foundation

/// Something the user copied.
public struct Clip: Identifiable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case text
        case link
        case image
    }

    /// How an image is stored and put back on the clipboard.
    public enum ImageFormat: String, Codable, Sendable {
        case png
        case jpeg

        /// The name the system uses for the format.
        public var typeIdentifier: String {
            switch self {
            case .png: "public.png"
            case .jpeg: "public.jpeg"
            }
        }
    }

    /// What is kept in memory about an image. The image itself stays on disk until it is needed.
    public struct ImageInfo: Equatable, Sendable, Codable {
        public var format: ImageFormat
        /// Size in pixels.
        public var width: Int
        public var height: Int
        /// The size of the stored image in bytes.
        public var byteCount: Int
        /// A fingerprint of the stored image, to recognise the same image copied again.
        public var digest: String
        /// A small PNG for the history list.
        public var thumbnail: Data

        public init(format: ImageFormat, width: Int, height: Int, byteCount: Int, digest: String, thumbnail: Data) {
            self.format = format
            self.width = width
            self.height = height
            self.byteCount = byteCount
            self.digest = digest
            self.thumbnail = thumbnail
        }
    }

    public let id: UUID
    public var kind: Kind
    /// The copied text. Empty for an image.
    public var text: String
    /// When it was first copied.
    public var created: Date
    /// When it was last copied, or last put back on the clipboard from Recall.
    public var used: Date
    /// Set for an image, nil for text and links.
    public var image: ImageInfo?

    public init(id: UUID = UUID(), kind: Kind, text: String, created: Date, used: Date, image: ImageInfo? = nil) {
        self.id = id
        self.kind = kind
        self.text = text
        self.created = created
        self.used = used
        self.image = image
    }

    public init(text: String, now: Date) {
        self.init(kind: .of(text), text: text, created: now, used: now)
    }

    public init(image: ImageInfo, now: Date) {
        self.init(kind: .image, text: "", created: now, used: now, image: image)
    }
}

extension Clip.Kind {
    /// A link is a single unbroken word that reads as an address: a scheme followed by a host,
    /// or a mail address after `mailto:`. Everything else is text.
    public static func of(_ text: String) -> Clip.Kind {
        let word = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !word.isEmpty, word.utf8.count <= 2048, !word.contains(where: \.isWhitespace),
              let components = URLComponents(string: word), let scheme = components.scheme?.lowercased()
        else { return .text }

        if scheme == "mailto" {
            return components.path.contains("@") ? .link : .text
        }
        guard word.dropFirst(scheme.count).hasPrefix("://") else { return .text }
        // A file address has no host, only a path.
        let hasTarget = scheme == "file" ? !components.path.isEmpty : !(components.host ?? "").isEmpty
        return hasTarget ? .link : .text
    }
}
