import Cocoa
import SwiftUI

class SettingsController: NSWindowController, NSWindowDelegate {
    static let shared: SettingsController = SettingsController()

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 480),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false)
        window.title = "Settings"
        window.contentMinSize = NSSize(width: 720, height: 480)
        window.isReleasedWhenClosed = false

        // Don't let the SwiftUI content constrain the window size.
        let hostingView = NSHostingView(rootView: SettingsView())
        hostingView.sizingOptions = []
        window.contentView = hostingView

        // Center first; the autosave name then restores any saved frame.
        window.center()
        window.setFrameAutosaveName("SettingsWindow")

        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: - Functions

    func show() {
        window?.makeKeyAndOrderFront(nil)
    }

    // MARK: - First Responder

    // This is called when "escape" is pressed.
    @objc func cancel(_ sender: Any?) {
        window?.performClose(sender)
    }
}
