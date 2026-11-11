import Cocoa
import GhosttyKit
import SwiftUI

class SettingsController: NSWindowController, NSWindowDelegate {
    static let shared: SettingsController = SettingsController()

    private let model: SettingsModel?
    private var watcher: ConfigFileWatcher?
    private var closedSignatures: [String: ConfigFileWatcher.Signature]?

    init() {
        let window = SettingsWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 480),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false)
        window.title = "Settings"
        window.contentMinSize = NSSize(width: 720, height: 480)
        window.isReleasedWhenClosed = false

        // Saving reloads the config, which posts a new one for the model. The watcher
        // takes our own write as seen so it doesn't reload a second time.
        weak var controller: SettingsController?
        let ghostty = (NSApp.delegate as? AppDelegate)?.ghostty
        let model = ghostty.map { ghostty in
            SettingsModel(
                config: ghostty.config,
                defaultTarget: ghostty.configPath ?? Ghostty.AllocatedString(ghostty_config_open_path()).string,
                onSaved: {
                    controller?.watcher?.rebaseline()
                    ghostty.reloadConfig()
                })
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
        controller = self
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
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        startWatching()
    }

    // MARK: - Config Files

    /// Reloads the app config when a config file changes while the window is open.
    private func startWatching() {
        guard watcher == nil, let model, let ghostty = (NSApp.delegate as? AppDelegate)?.ghostty else { return }
        watcher = ConfigFileWatcher(paths: model.files) { [weak ghostty] in ghostty?.reloadConfig() }

        // Files edited while closed; the reload refreshes the model via the config change.
        if let closedSignatures, closedSignatures != ConfigFileWatcher.signatures(paths: model.files) {
            ghostty.reloadConfig()
        }
        closedSignatures = nil
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
        closedSignatures = model.map { ConfigFileWatcher.signatures(paths: $0.files) }
    }

    // MARK: - First Responder

    @IBAction func close(_ sender: Any) {
        window?.performClose(sender)
    }

    @IBAction func closeWindow(_ sender: Any) {
        window?.performClose(sender)
    }

    // This is called when "escape" is pressed.
    @objc func cancel(_ sender: Any?) {
        window?.performClose(sender)
    }
}

/// Sends the standard edit shortcuts to the focused field. Copy and paste are
/// performable bindings, which aren't menu shortcuts, so the menu never does.
final class SettingsWindow: NSWindow {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if super.performKeyEquivalent(with: event) { return true }
        guard let key = event.charactersIgnoringModifiers?.lowercased(),
              let action = Self.editAction(key: key, modifiers: event.modifierFlags) else { return false }
        return NSApp.sendAction(action, to: nil, from: self)
    }

    static func editAction(key: String, modifiers: NSEvent.ModifierFlags) -> Selector? {
        switch (key, modifiers.intersection([.command, .shift, .option, .control])) {
        case ("x", .command): #selector(NSText.cut(_:))
        case ("c", .command): #selector(NSText.copy(_:))
        case ("v", .command): #selector(NSText.paste(_:))
        case ("a", .command): #selector(NSResponder.selectAll(_:))
        case ("z", .command): Selector(("undo:"))
        case ("z", [.command, .shift]): Selector(("redo:"))
        default: nil
        }
    }
}
