import AppKit
import SwiftUI

/// The floating history window. It takes keyboard input without making Recall the active app,
/// so the app the user came from stays in front and gets focus back when the panel closes.
final class HistoryPanel: NSPanel {
    /// Sees every key press first. Returns true when the key has been dealt with.
    var keyHandler: (@MainActor (NSEvent) -> Bool)?

    init() {
        super.init(
            contentRect: NSRect(origin: .zero, size: HistoryPanelController.size),
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
            backing: .buffered, defer: false)
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
        animationBehavior = .none
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            standardWindowButton(button)?.isHidden = true
        }
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    // Command shortcuts arrive here before they reach the menu bar…
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.type == .keyDown, keyHandler?(event) == true { return true }
        return super.performKeyEquivalent(with: event)
    }

    // …and every other key arrives here before it reaches the search field.
    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, keyHandler?(event) == true { return }
        super.sendEvent(event)
    }
}

/// Creates the panel once and shows, hides, places and focuses it.
@MainActor
final class HistoryPanelController: NSObject, NSWindowDelegate {
    static let size = NSSize(width: 460, height: 420)

    let panel = HistoryPanel()
    /// Called when the panel stops being the window that receives keys.
    var onResignKey: (() -> Void)?

    init(rootView: some View, keyHandler: @escaping @MainActor (NSEvent) -> Bool) {
        super.init()

        let background = NSVisualEffectView()
        background.material = .popover
        background.blendingMode = .behindWindow
        background.state = .active
        let hosting = NSHostingView(rootView: rootView)
        hosting.frame = background.bounds
        hosting.autoresizingMask = [.width, .height]
        background.addSubview(hosting)

        panel.contentView = background
        panel.keyHandler = keyHandler
        panel.delegate = self
    }

    var isVisible: Bool { panel.isVisible }
    var hasFocus: Bool { panel.isVisible && panel.isKeyWindow }

    func show() {
        if !panel.isVisible { place() }
        panel.makeKeyAndOrderFront(nil)
        focusSearchField()
    }

    func hide() {
        panel.orderOut(nil)
    }

    /// Puts the insertion point in the search field. SwiftUI's own focus handling is not
    /// dependable the first time a view appears in a panel, so this goes straight to AppKit,
    /// once now and once after SwiftUI has had a chance to build the view.
    func focusSearchField() {
        applyFocus()
        DispatchQueue.main.async { [weak self] in self?.applyFocus() }
    }

    private func applyFocus() {
        guard panel.isVisible, let root = panel.contentView,
              let field = root.firstDescendant(where: { ($0 as? NSTextField)?.isEditable ?? false }) as? NSTextField
        else { return }
        // A text field is being edited when its field editor is first responder.
        if panel.firstResponder !== field, field.currentEditor() == nil {
            panel.makeFirstResponder(field)
        }
    }

    /// The upper middle of the screen that has the pointer.
    private func place() {
        let pointer = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(pointer, $0.frame, false) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let size = Self.size
        let origin = NSPoint(
            x: visible.midX - size.width / 2,
            y: visible.maxY - size.height - visible.height * 0.16)
        panel.setFrame(NSRect(origin: origin, size: size), display: false)
    }

    func windowDidResignKey(_ notification: Notification) { onResignKey?() }
}

private extension NSView {
    func firstDescendant(where matches: (NSView) -> Bool) -> NSView? {
        for subview in subviews {
            if matches(subview) { return subview }
            if let found = subview.firstDescendant(where: matches) { return found }
        }
        return nil
    }
}
