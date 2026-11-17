/// The modifier keys that take part in shortcuts.
public struct KeyModifiers: OptionSet, Codable, Hashable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let command = KeyModifiers(rawValue: 1 << 0)
    public static let shift = KeyModifiers(rawValue: 1 << 1)
    public static let option = KeyModifiers(rawValue: 1 << 2)
    public static let control = KeyModifiers(rawValue: 1 << 3)
}

/// A key pressed together with modifiers.
///
/// `keyCode` is the hardware key, the same on every keyboard layout. `character` is what that
/// key types on the current layout, so that ⌘W is the key marked W whether the keyboard is
/// Swedish, French or German.
public struct KeyPress: Equatable, Sendable {
    public var keyCode: UInt16
    public var modifiers: KeyModifiers
    public var character: String?

    public init(keyCode: UInt16, modifiers: KeyModifiers, character: String? = nil) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.character = character
    }
}

/// What the panel does in response to a key.
public enum KeyCommand: Equatable, Sendable {
    case close
    case moveUp
    case moveDown
    case copySelected
    case deleteSelected
    case settings
}

/// The panel's key table. Keys that are not listed go to the search field as usual.
public enum KeyRouter {
    private enum Key {
        static let returnKey: UInt16 = 36
        static let delete: UInt16 = 51
        static let escape: UInt16 = 53
        static let enter: UInt16 = 76
        static let down: UInt16 = 125
        static let up: UInt16 = 126
    }

    /// The characters of the shortcut keys on a US keyboard, by key code. Used when the
    /// current layout gives no Latin character for a key.
    public static let usCharacters: [UInt16: String] = [
        8: "c", 12: "q", 13: "w", 43: ",",
    ]

    public static func command(for press: KeyPress, focus: HistoryList.Focus) -> KeyCommand? {
        let inList = focus == .list

        // Keys without a character are matched by position.
        switch (press.keyCode, press.modifiers) {
        case (Key.escape, []):
            return .close
        case (Key.down, []):
            return .moveDown
        case (Key.up, []):
            return .moveUp
        case (Key.returnKey, []), (Key.enter, []):
            return .copySelected
        case (Key.delete, .command):
            // In the search field ⌘⌫ clears the query, as in any text field.
            return inList ? .deleteSelected : nil
        default:
            break
        }

        // Letters are matched by what the key types.
        switch (press.character?.lowercased(), press.modifiers) {
        case ("w", .command), ("q", .command):
            return .close
        case (",", .command):
            return .settings
        case ("c", .command):
            // In the search field ⌘C copies the selected part of the query.
            return inList ? .copySelected : nil
        default:
            return nil
        }
    }

    /// Holding a key down repeats it. Only moving through the list should repeat;
    /// a held ⌘⌫ must not delete one clip after another.
    public static func repeatsWhenHeld(_ command: KeyCommand) -> Bool {
        command == .moveUp || command == .moveDown
    }

    /// True for a key whose repeats are dropped wherever focus is. Deleting the last row
    /// moves focus to the search field, and a ⌘⌫ still held down must not go on to clear the query.
    public static func swallowsRepeat(_ press: KeyPress) -> Bool {
        command(for: press, focus: .list) == .deleteSelected
    }

    /// True for a key that is meant for the search field although the list has focus:
    /// anything typed without Command or Control that is not part of the key table.
    public static func returnsFocusToSearch(_ press: KeyPress, focus: HistoryList.Focus) -> Bool {
        guard focus == .list, command(for: press, focus: focus) == nil else { return false }
        return press.modifiers.isDisjoint(with: [.command, .control])
    }
}
