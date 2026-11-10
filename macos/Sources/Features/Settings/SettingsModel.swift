import Foundation
import GhosttyKit

enum SettingsSection: String, CaseIterable, Identifiable {
    case font = "Font"
    case appearance = "Appearance"
    case window = "Window"
    case clipboard = "Clipboard"
    case mouse = "Mouse"
    case keybindings = "Keybindings"
    case shellIntegration = "Shell integration"
    case quickTerminal = "Quick terminal"
    case macos = "macOS"
    case linux = "Linux/GTK"
    case advanced = "Advanced"

    var id: String { rawValue }
}

@MainActor
final class SettingsModel: ObservableObject {
    enum EditResult: Equatable {
        case ok
        case failed(String)
    }

    @Published var options: [SettingsOption] = []
    @Published var files: [String] = []
    @Published var search: String = ""
    @Published var selectedSection: SettingsSection?
    @Published var selectedFile: String?

    let defaultTarget: String
    private let onSaved: () -> Void
    private var schema: SettingsSchema?

    init(config: Ghostty.Config, defaultTarget: String, onSaved: @escaping () -> Void = {}) {
        self.defaultTarget = defaultTarget
        self.onSaved = onSaved
        reload(config: config)
    }

    func reload(config: Ghostty.Config) {
        let schema = SettingsSchema(config: config)
        self.schema = schema
        options = schema.options
        files = schema.files
        if let file = selectedFile, !files.contains(file) { selectedFile = nil }
    }

    // MARK: - Labels and sections

    private static let acronyms = [
        "macos": "macOS", "gtk": "GTK", "osc": "OSC", "url": "URL", "ui": "UI", "x11": "X11",
    ]

    /// "macos-titlebar-style" -> "macOS titlebar style"
    static func label(for key: String) -> String {
        key.split(separator: "-").enumerated().map { i, part in
            let word = String(part)
            if let acronym = acronyms[word] { return acronym }
            return i == 0 ? word.prefix(1).uppercased() + word.dropFirst() : word
        }.joined(separator: " ")
    }

    /// Matched against whole dash-separated words, longest prefix first.
    private static let sectionPrefixes: [(String, SettingsSection)] = [
        ("font", .font), ("adjust", .font), ("freetype", .font),
        ("background", .appearance), ("foreground", .appearance), ("palette", .appearance),
        ("theme", .appearance), ("cursor", .appearance), ("selection", .appearance),
        ("minimum-contrast", .appearance), ("bold", .appearance), ("faint", .appearance),
        ("alpha", .appearance),
        ("window", .window), ("maximize", .window), ("fullscreen", .window),
        ("resize-overlay", .window), ("unfocused-split", .window), ("split", .window),
        ("clipboard", .clipboard), ("copy-on-select", .clipboard),
        ("mouse", .mouse), ("focus-follows-mouse", .mouse), ("click-repeat-interval", .mouse),
        ("keybind", .keybindings),
        ("shell-integration", .shellIntegration),
        ("quick-terminal", .quickTerminal),
        ("macos", .macos),
        ("gtk", .linux), ("linux", .linux), ("x11", .linux), ("adw", .linux),
    ].sorted { $0.0.count > $1.0.count }

    static func section(for key: String) -> SettingsSection {
        sectionPrefixes.first { key == $0.0 || key.hasPrefix($0.0 + "-") }?.1 ?? .advanced
    }

    // MARK: - Filtering

    var visibleOptions: [SettingsOption] {
        let query = search.trimmingCharacters(in: .whitespaces)
        return options.filter { option in
            if !query.isEmpty {
                guard option.key.localizedCaseInsensitiveContains(query)
                    || Self.label(for: option.key).localizedCaseInsensitiveContains(query)
                    || option.help.localizedCaseInsensitiveContains(query) else { return false }
            }
            if let file = selectedFile {
                guard ([option.source] + option.entrySources).contains(where: { $0.filePath == file }) else { return false }
            }
            if query.isEmpty, let section = selectedSection {
                return Self.section(for: option.key) == section
            }
            return true
        }
    }

    // MARK: - Writing

    /// An explicit choice wins, then the option's own file. Themes are never written.
    func writeTarget(for option: SettingsOption, choice: String?) -> String {
        if let choice { return choice }
        if case .file(let path, _) = option.source { return path }
        return defaultTarget
    }

    /// Warns when the file that set the option loads after `target`, or `target` isn't loaded yet.
    func overrideWarning(option: SettingsOption, target: String) -> String? {
        guard case .file(let source, _) = option.source, source != target else { return nil }
        if let targetIndex = files.firstIndex(of: target) {
            guard let sourceIndex = files.firstIndex(of: source), targetIndex < sourceIndex else { return nil }
        }
        let basename = (source as NSString).lastPathComponent
        return "⚠ \(basename) sets this later and will override it."
    }

    func apply(_ op: ghostty_config_edit_op_e, key: String, value: String?, target: String) -> EditResult {
        let result = key.withCString { k in
            Self.withOptionalCString(value) { v in
                ghostty_config_edit(target, op, k, UInt(key.utf8.count), v, UInt(value?.utf8.count ?? 0))
            }
        }

        let file = (target as NSString).lastPathComponent
        switch result {
        case GHOSTTY_CONFIG_EDIT_OK:
            onSaved()
            return .ok
        case GHOSTTY_CONFIG_EDIT_UNKNOWN_KEY: return .failed("Unknown option \(key)")
        case GHOSTTY_CONFIG_EDIT_INVALID_VALUE: return .failed("Invalid value for \(key)")
        case GHOSTTY_CONFIG_EDIT_REPEATABLE_KEY: return .failed("\(key) is a list; add or remove entries instead")
        case GHOSTTY_CONFIG_EDIT_DANGLING_SYMLINK: return .failed("\(file) is a broken symlink")
        case GHOSTTY_CONFIG_EDIT_HARD_LINK: return .failed("\(file) has multiple hard links and can't be rewritten")
        case GHOSTTY_CONFIG_EDIT_ACCESS_DENIED: return .failed("Permission denied writing \(file)")
        default: return .failed("Couldn't save \(file)")
        }
    }

    private static func withOptionalCString<R>(_ s: String?, _ body: (UnsafePointer<CChar>?) -> R) -> R {
        guard let s else { return body(nil) }
        return s.withCString(body)
    }
}

private extension SettingsSource {
    var filePath: String? {
        if case .file(let path, _) = self { return path }
        return nil
    }
}
