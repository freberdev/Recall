import Foundation

/// Something the user copied.
public struct Clip: Identifiable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case text
        case link
    }

    public let id: UUID
    public var kind: Kind
    public var text: String
    /// When it was first copied.
    public var created: Date
    /// When it was last copied, or last put back on the clipboard from Recall.
    public var used: Date

    public init(id: UUID = UUID(), kind: Kind, text: String, created: Date, used: Date) {
        self.id = id
        self.kind = kind
        self.text = text
        self.created = created
        self.used = used
    }

    public init(text: String, now: Date) {
        self.init(kind: .of(text), text: text, created: now, used: now)
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
