import Foundation

/// A global keyboard shortcut: a hardware key together with modifier keys.
public struct Shortcut: Codable, Equatable, Sendable {
    /// The virtual key code, independent of keyboard layout.
    public var keyCode: UInt32
    public var modifiers: KeyModifiers

    public init(keyCode: UInt32, modifiers: KeyModifiers) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// ⇧⌘V
    public static let `default` = Shortcut(keyCode: 9, modifiers: [.command, .shift])

    /// A shortcut must include Command or Control. Option with a key types a character
    /// on many layouts (@, |, [ and ] on a Swedish keyboard), so Option alone is not enough.
    public var isValid: Bool {
        !modifiers.isDisjoint(with: [.command, .control])
    }

    /// The modifiers as the Carbon hot key API expects them.
    public var carbonModifiers: UInt32 {
        var flags: UInt32 = 0
        if modifiers.contains(.command) { flags |= 0x0100 }
        if modifiers.contains(.shift) { flags |= 0x0200 }
        if modifiers.contains(.option) { flags |= 0x0800 }
        if modifiers.contains(.control) { flags |= 0x1000 }
        return flags
    }

    /// The modifier symbols in the order macOS shows them: ⌃⌥⇧⌘.
    public var modifierSymbols: String {
        var symbols = ""
        if modifiers.contains(.control) { symbols += "⌃" }
        if modifiers.contains(.option) { symbols += "⌥" }
        if modifiers.contains(.shift) { symbols += "⇧" }
        if modifiers.contains(.command) { symbols += "⌘" }
        return symbols
    }
}
