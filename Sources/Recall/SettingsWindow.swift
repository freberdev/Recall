import AppKit
import SwiftUI

/// The settings window. Recall has no Dock icon, so the window is created and brought forward by hand;
/// SwiftUI's own Settings scene tends to open behind other apps in that situation.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    /// Called when the window closes or stops being the key window.
    var onInactive: (() -> Void)?

    private var window: NSWindow?
    private let makeContent: () -> AnyView

    init(content: @escaping () -> some View) {
        makeContent = { AnyView(content()) }
    }

    func show() {
        if window == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: makeContent()))
            window.title = L("settings.title")
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            self.window = window
        }
        // Recall is not the active app when this is called from the history panel or the menu bar.
        NSApp.activateInsistently()
        window?.makeKeyAndOrderFront(nil)
    }

    var isVisible: Bool { window?.isVisible ?? false }

    func windowDidResignKey(_ notification: Notification) { onInactive?() }

    func windowWillClose(_ notification: Notification) {
        onInactive?()
        // Once the window is gone Recall has nothing to show, but it would stay the active app.
        DispatchQueue.main.async { NSApp.returnToPreviousApp() }
    }
}

extension NSApplication {
    /// Makes Recall the active app even when another app is in front.
    ///
    /// The cooperative `activate()` is only a request, and it is ignored when Recall is not already
    /// active, which is always the case for an app that lives in the menu bar.
    func activateInsistently() {
        (self as InsistentActivation).activate(ignoringOtherApps: true)
    }
}

extension NSApplication {
    /// Gives the keyboard back to the app that was in front before Recall was made active.
    ///
    /// Recall has no Dock icon and no main window, so nothing does this for it. Without it
    /// the next ⌘V after choosing a clip would go to Recall, which has nowhere to paste.
    func returnToPreviousApp() {
        guard isActive else { return }
        hide(nil)
    }
}

/// Reaches `activate(ignoringOtherApps:)` without a deprecation warning at the call site.
@MainActor
private protocol InsistentActivation {
    func activate(ignoringOtherApps flag: Bool)
}

extension NSApplication: InsistentActivation {}
