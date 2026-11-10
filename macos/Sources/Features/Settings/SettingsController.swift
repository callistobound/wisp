import Cocoa
import GhosttyKit
import SwiftUI

class SettingsController: NSWindowController, NSWindowDelegate {
    static let shared: SettingsController = SettingsController()

    private let model: SettingsModel?
    private var watcher: ConfigFileWatcher?

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 480),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false)
        window.title = "Settings"
        window.contentMinSize = NSSize(width: 720, height: 480)
        window.isReleasedWhenClosed = false

        // Saving reloads the config, which posts a new one for the model.
        let ghostty = (NSApp.delegate as? AppDelegate)?.ghostty
        let model = ghostty.map { ghostty in
            SettingsModel(
                config: ghostty.config,
                defaultTarget: ghostty.configPath ?? Ghostty.AllocatedString(ghostty_config_open_path()).string,
                onSaved: { ghostty.reloadConfig() })
        }

        // Don't let the SwiftUI content constrain the window size.
        if let ghostty, let model {
            let hostingView = NSHostingView(rootView: SettingsView(model: model, openInEditor: ghostty.openInEditor))
            hostingView.sizingOptions = []
            window.contentView = hostingView
        }

        // Center first; the autosave name then restores any saved frame.
        window.center()
        window.setFrameAutosaveName("SettingsWindow")

        self.model = model
        super.init(window: window)
        window.delegate = self

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(ghosttyConfigDidChange(_:)),
            name: .ghosttyConfigDidChange,
            object: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: - Functions

    func show() {
        window?.makeKeyAndOrderFront(nil)
        startWatching()
    }

    // MARK: - Config Files

    /// Reloads the app config when a config file changes while the window is open.
    private func startWatching() {
        guard watcher == nil, let model, let ghostty = (NSApp.delegate as? AppDelegate)?.ghostty else { return }
        watcher = ConfigFileWatcher(paths: model.files) { [weak ghostty] in ghostty?.reloadConfig() }
    }

    @objc private func ghosttyConfigDidChange(_ notification: Notification) {
        // Only app-level configs; surface configs are posted with the surface as the object.
        guard notification.object == nil,
              let config = notification.userInfo?[Notification.Name.GhosttyConfigChangeKey] as? Ghostty.Config,
              let model else { return }
        model.reload(config: config)
        watcher?.update(paths: model.files)
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        watcher = nil
    }

    // MARK: - First Responder

    // This is called when "escape" is pressed.
    @objc func cancel(_ sender: Any?) {
        window?.performClose(sender)
    }
}
