import RecallCore
import SwiftUI

@main
struct RecallApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            MenuContent(model: delegate.model)
        } label: {
            MenuBarLabel(model: delegate.model)
        }
    }
}

/// The menu bar icon. It changes while collecting is paused, so the state is visible at a glance.
private struct MenuBarLabel: View {
    let model: AppModel

    var body: some View {
        Image(systemName: model.isPaused ? "pause.circle" : "clipboard")
            .accessibilityLabel(model.isPaused ? L("menu.label.paused") : L("menu.label"))
    }
}

private struct MenuContent: View {
    let model: AppModel

    var body: some View {
        Button(L("menu.open", model.shortcutDisplay)) { model.showPanel() }
        Divider()
        if model.isPaused {
            Button(L("menu.resume")) { model.setPaused(false) }
        } else {
            Button(L("menu.pause")) { model.setPaused(true) }
        }
        Button(L("menu.clear")) { model.confirmClearHistory() }
            .disabled(!model.store.hasAnythingToClear)
        Divider()
        Button(L("menu.settings")) { model.openSettings() }
        Divider()
        Button(L("menu.quit")) { NSApplication.shared.terminate(nil) }
    }
}
