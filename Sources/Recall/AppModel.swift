import AppKit
import Observation
import RecallCore
import SwiftUI

/// Ties the history, the clipboard, the panel and the global shortcut together.
@MainActor @Observable
final class AppModel {
    /// True while nothing is collected from the clipboard.
    private(set) var isPaused: Bool
    /// Whether macOS lets Recall read the clipboard.
    private(set) var clipboardAccess: ClipboardAccess = .allowed

    /// The global shortcut that opens Recall.
    private(set) var shortcut: Shortcut
    /// Something the user should know about the shortcut they just chose, or nil.
    var shortcutMessage: String?
    /// True while the settings window is waiting for the user to press a new shortcut.
    private(set) var isRecordingShortcut = false

    let store: HistoryStore
    let list: HistoryList

    @ObservationIgnored private let preferences = Preferences()
    @ObservationIgnored private let clipboard = SystemClipboard()
    @ObservationIgnored private let watcher: ClipboardWatcher
    @ObservationIgnored private let hotKey = HotKey()
    @ObservationIgnored private var panel: HistoryPanelController?
    @ObservationIgnored private var settingsWindow: SettingsWindowController?
    @ObservationIgnored private var shortcutMonitor: Any?
    @ObservationIgnored private var timers: [Timer] = []

    /// How often the clipboard's change count is compared. Reading happens only when it has changed.
    private static let pollInterval: TimeInterval = 0.5
    private static let pruneInterval: TimeInterval = 3600

    init() {
        // "-historyDirectory <path>" on the command line points Recall at another folder, for development.
        let custom = UserDefaults.standard.string(forKey: "historyDirectory")
            .map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath, isDirectory: true) }
        let directory = custom ?? ClipFiles.defaultDirectory
        // A folder of its own gets a key of its own, so development never touches the real one.
        let account = custom.map { "history-key \($0.path)" } ?? "history-key"
        let cipher = (try? Keychain.historyKey(account: account)).flatMap(ClipCipher.init(keyData:))

        store = HistoryStore(files: ClipFiles(directory: directory, cipher: cipher), limits: preferences.limits)
        list = HistoryList(store: store)
        isPaused = preferences.isPaused
        shortcut = preferences.shortcut
        watcher = ClipboardWatcher(source: clipboard, store: store, isPaused: preferences.isPaused)
    }

    /// Called once the app has launched: reads the history, builds the panel and claims the shortcut.
    func start() {
        store.load(now: Date())
        clipboardAccess = clipboard.access

        let controller = HistoryPanelController(rootView: HistoryView(model: self, list: list)) { [weak self] event in
            self?.handleKey(event) ?? false
        }
        controller.onResignKey = { [weak self] in self?.closePanel() }
        panel = controller

        hotKey.onPressed = { [weak self] in self?.hotKeyPressed() }
        resumeHotKey()

        let settings = SettingsWindowController { [unowned self] in SettingsView(model: self) }
        settings.onInactive = { [weak self] in self?.stopRecordingShortcut() }
        settingsWindow = settings

        watcher.start()
        schedule(every: Self.pollInterval, tolerance: 0.1) { $0.pollClipboard() }
        schedule(every: Self.pruneInterval, tolerance: 60) { $0.removeExpired() }

        enableLoginItemOnce()
        if !preferences.hasShownWelcome {
            preferences.hasShownWelcome = true
            showPanel()
        }
    }

    private func schedule(every interval: TimeInterval, tolerance: TimeInterval, _ work: @escaping @MainActor (AppModel) -> Void) {
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            // Timers on the main run loop fire on the main thread.
            MainActor.assumeIsolated {
                guard let self else { return }
                work(self)
            }
        }
        timer.tolerance = tolerance
        // Common modes, so that the clipboard is also watched while a menu is open.
        RunLoop.main.add(timer, forMode: .common)
        timers.append(timer)
    }

    /// Recall is of little use if it is not running after a restart, so "open at login" is
    /// turned on the first time Recall runs from the Applications folder. Only ever once:
    /// after that the choice belongs to the user.
    private func enableLoginItemOnce() {
        guard LoginItem.isInstalled, !preferences.didAutoEnableLoginItem else { return }
        preferences.didAutoEnableLoginItem = true
        try? LoginItem.setEnabled(true)
    }

    // MARK: Collecting

    private func pollClipboard() {
        let access = clipboard.access
        if access != clipboardAccess { clipboardAccess = access }
        watcher.poll()
    }

    /// Drops clips that have become too old. Called on a timer and when the Mac wakes.
    func removeExpired() {
        store.prune(now: Date())
    }

    func setPaused(_ paused: Bool) {
        guard paused != isPaused else { return }
        isPaused = paused
        preferences.isPaused = paused
        watcher.isPaused = paused
    }

    func openClipboardSettings() {
        guard let url = SystemClipboard.settingsURL else { return }
        closePanel()
        NSWorkspace.shared.open(url)
    }

    // MARK: Opening and closing

    /// Closed, or open without focus: show with focus. Open with focus: close.
    func hotKeyPressed() {
        if panel?.hasFocus == true {
            closePanel()
        } else {
            showPanel()
        }
    }

    func showPanel() {
        guard let panel else { return }
        if !panel.isVisible { list.reset() }
        // Recall hides itself after its settings window closes. Its panel can only be shown
        // once it is unhidden, and it must not become the active app in the process.
        if NSApp.isHidden { NSApp.unhideWithoutActivation() }
        panel.show()
    }

    func closePanel() {
        panel?.hide()
    }

    // MARK: Acting on clips

    /// Puts a clip back on the clipboard, moves it to the top and closes the panel.
    /// The app the user came from is still in front, ready for ⌘V.
    func copy(_ clip: Clip) {
        // Something copied a moment ago may not have been seen yet. Record it first, or
        // Recall's own write would hide it.
        watcher.poll()
        let changeCount = clipboard.write(clip.text)
        watcher.ignoreChange(changeCount)
        store.markUsed(id: clip.id, now: Date())
        closePanel()
    }

    func delete(_ clip: Clip) {
        do { try store.delete(id: clip.id) } catch { NSSound.beep() }
    }

    private func deleteSelected() {
        do { try list.deleteSelected() } catch { NSSound.beep() }
    }

    func clearHistory() {
        do {
            try store.deleteAll()
            list.reset()
        } catch {
            NSSound.beep()
        }
    }

    /// Asks first. Used from the menu bar, where there is no window to hold a confirmation.
    func confirmClearHistory() {
        closePanel()
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L("settings.clear.title")
        alert.informativeText = L("settings.clear.message")
        alert.addButton(withTitle: L("settings.clear.confirm"))
        alert.addButton(withTitle: L("settings.clear.cancel"))
        alert.buttons.first?.hasDestructiveAction = true
        NSApp.activateInsistently()
        if alert.runModal() == .alertFirstButtonReturn { clearHistory() }
        if settingsWindow?.isVisible != true { NSApp.returnToPreviousApp() }
    }

    // MARK: Settings

    func openSettings() {
        closePanel()
        settingsWindow?.show()
    }

    var limits: Limits { store.limits }

    func setLimits(_ limits: Limits) {
        preferences.limits = limits
        store.setLimits(limits, now: Date())
    }

    var historyFolderDisplay: String {
        // Inside the sandbox the home folder is the app's container, so the real path is shown as it is.
        store.directory.path.replacingOccurrences(of: "/Users/\(NSUserName())/", with: "~/")
    }

    func revealHistoryFolder() {
        try? FileManager.default.createDirectory(
            at: store.directory, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        NSWorkspace.shared.open(store.directory)
    }

    /// The shortcut as the user sees it, for example "⇧⌘V".
    var shortcutDisplay: String {
        shortcut.modifierSymbols + KeyNames.name(for: shortcut.keyCode)
    }

    private func resumeHotKey() {
        hotKey.register(keyCode: shortcut.keyCode, carbonModifiers: shortcut.carbonModifiers)
    }

    /// Waits for the next key combination and makes it the shortcut. Escape cancels.
    func startRecordingShortcut() {
        guard !isRecordingShortcut else { return }
        isRecordingShortcut = true
        shortcutMessage = nil
        // The current shortcut must not fire while the user is choosing a new one.
        hotKey.unregister()
        shortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.recordShortcut(from: event)
            return nil
        }
    }

    /// Ends recording and puts the shortcut back in force. Also called when the settings
    /// window closes or loses focus, so the shortcut can never be left switched off.
    func stopRecordingShortcut() {
        guard isRecordingShortcut else { return }
        isRecordingShortcut = false
        if let shortcutMonitor { NSEvent.removeMonitor(shortcutMonitor) }
        shortcutMonitor = nil
        resumeHotKey()
    }

    private func recordShortcut(from event: NSEvent) {
        let modifiers = KeyModifiers(event.modifierFlags)
        if event.keyCode == 53, modifiers.isEmpty {
            stopRecordingShortcut()
            return
        }
        let candidate = Shortcut(keyCode: UInt32(event.keyCode), modifiers: modifiers)
        guard candidate.isValid else {
            shortcutMessage = L("settings.shortcut.needsModifier")
            return
        }
        stopRecordingShortcut()
        setShortcut(candidate)
    }

    /// Switches to a new shortcut. If the system refuses it, the previous one stays.
    private func setShortcut(_ new: Shortcut) {
        if hotKey.register(keyCode: new.keyCode, carbonModifiers: new.carbonModifiers) {
            shortcut = new
            preferences.shortcut = new
            shortcutMessage = nil
        } else {
            resumeHotKey()
            shortcutMessage = L("settings.shortcut.refused")
        }
    }

    // MARK: Keys

    private func handleKey(_ event: NSEvent) -> Bool {
        // Let an input method finish composing before any key is taken away from it.
        if let textView = panel?.panel.firstResponder as? NSTextView, textView.hasMarkedText() {
            return false
        }
        let press = RecallCore.KeyPress(event)
        if event.isARepeat, KeyRouter.swallowsRepeat(press) { return true }
        guard let command = KeyRouter.command(for: press, focus: list.focus) else {
            // Typing while the list has focus continues the search.
            if KeyRouter.returnsFocusToSearch(press, focus: list.focus) { list.focus = .search }
            return false
        }
        // A held key is swallowed rather than repeated, except for moving through the list.
        if !event.isARepeat || KeyRouter.repeatsWhenHeld(command) {
            perform(command)
        }
        return true
    }

    private func perform(_ command: KeyCommand) {
        switch command {
        case .close: closePanel()
        case .moveUp: list.moveSelection(by: -1)
        case .moveDown: list.moveSelection(by: 1)
        case .copySelected: if let clip = list.selected { copy(clip) }
        case .deleteSelected: deleteSelected()
        case .settings: openSettings()
        }
    }
}

extension RecallCore.KeyPress {
    /// The key and modifiers of an event, with the character the key types on the current layout.
    init(_ event: NSEvent) {
        // With Command held, most non-Latin layouts report a Latin character in `characters`.
        // Control and Option change `characters` to something else, so the unmodified one is tried too.
        let candidates = [event.characters, event.charactersIgnoringModifiers]
        let character = candidates.compactMap { $0 }.first { text in
            text.unicodeScalars.count == 1 && text.unicodeScalars.allSatisfy { (0x21...0x7E).contains($0.value) }
        }
        self.init(
            keyCode: event.keyCode,
            modifiers: KeyModifiers(event.modifierFlags),
            character: character ?? KeyRouter.usCharacters[event.keyCode])
    }
}

extension KeyModifiers {
    init(_ flags: NSEvent.ModifierFlags) {
        self = []
        if flags.contains(.command) { insert(.command) }
        if flags.contains(.shift) { insert(.shift) }
        if flags.contains(.option) { insert(.option) }
        if flags.contains(.control) { insert(.control) }
    }
}
