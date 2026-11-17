import AppKit
import RecallCore

/// Whether macOS lets Recall read the clipboard without the user pasting.
enum ClipboardAccess {
    /// Recall may read whenever the clipboard changes.
    case allowed
    /// macOS asks the user every time Recall reads.
    case asks
    /// macOS refuses every read.
    case denied
}

/// The system clipboard.
@MainActor
final class SystemClipboard: ClipboardSource {
    private let pasteboard = NSPasteboard.general

    var changeCount: Int { pasteboard.changeCount }

    var types: [String] {
        (pasteboard.types ?? []).map(\.rawValue)
    }

    /// Reads only while macOS allows it without asking. Otherwise every copy the user makes
    /// would bring up a question from the system.
    func readString() -> String? {
        guard access == .allowed else { return nil }
        return pasteboard.string(forType: .string)
    }

    /// Replaces the contents with `text` and returns the change count after the write.
    func write(_ text: String) -> Int {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        return pasteboard.changeCount
    }

    /// The user's choice under Privacy & Security in System Settings.
    ///
    /// Until macOS has asked for the first time there is no choice, and reading is what makes
    /// it ask. After that Recall waits for the user to allow it for good.
    var access: ClipboardAccess {
        switch pasteboard.accessBehavior {
        case .alwaysAllow, .default: .allowed
        case .alwaysDeny: .denied
        case .ask: .asks
        @unknown default: .asks
        }
    }

    /// The part of System Settings where the choice is made.
    static let settingsURL = URL(
        string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Pasteboard")
}
