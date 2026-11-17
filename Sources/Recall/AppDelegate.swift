import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // "-appearance dark" or "-appearance light" on the command line overrides the system, for development.
        switch UserDefaults.standard.string(forKey: "appearance") {
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        default: break
        }

        model.start()

        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(didWake), name: NSWorkspace.didWakeNotification, object: nil)
    }

    /// Opening Recall again while it is running, from Spotlight or Finder, shows the panel.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        model.showPanel()
        return false
    }

    /// Timers do not run while the Mac sleeps, so what has grown too old is removed on waking.
    @objc private func didWake(_ notification: Notification) {
        model.removeExpired()
    }
}
