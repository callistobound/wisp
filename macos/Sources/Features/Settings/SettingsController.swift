import Cocoa
import Combine
import GhosttyKit
import SwiftUI

class SettingsController: NSWindowController, NSWindowDelegate {
    static let shared: SettingsController = SettingsController()

    private var configCancellable: AnyCancellable?

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 480),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false)
        window.title = "Settings"
        window.contentMinSize = NSSize(width: 720, height: 480)
        window.isReleasedWhenClosed = false

        // Saving reloads the config, which publishes a new one for the model.
        let ghostty = (NSApp.delegate as? AppDelegate)?.ghostty
        let model = ghostty.map { ghostty in
            SettingsModel(
                config: ghostty.config,
                defaultTarget: ghostty.configPath ?? Ghostty.AllocatedString(ghostty_config_open_path()).string,
                onSaved: { ghostty.reloadConfig() })
        }

        // Don't let the SwiftUI content constrain the window size.
        if let model {
            let hostingView = NSHostingView(rootView: SettingsView(model: model))
            hostingView.sizingOptions = []
            window.contentView = hostingView
        }

        // Center first; the autosave name then restores any saved frame.
        window.center()
        window.setFrameAutosaveName("SettingsWindow")

        super.init(window: window)
        window.delegate = self

        configCancellable = ghostty?.$config.dropFirst().sink { [weak model] config in
            Task { @MainActor in model?.reload(config: config) }
        }
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
