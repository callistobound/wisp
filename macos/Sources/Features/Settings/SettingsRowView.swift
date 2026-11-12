import SwiftUI
import GhosttyKit

/// One option: label, key, control, source picker and help.
struct SettingsRowView: View {
    @ObservedObject var model: SettingsModel
    let option: SettingsOption

    @State private var selection: String
    @State private var error: String?

    init(model: SettingsModel, option: SettingsOption) {
        self.model = model
        self.option = option
        _selection = State(initialValue: SourcePicker.initial(for: option.source))
    }

    /// The file a reset unsets the option in: only options set by a config file.
    /// Never keybinds, since unsetting would drop every binding in the file.
    static func resetFile(for option: SettingsOption) -> String? {
        if option.kind != .keybind, case .file(let path, _) = option.source { return path }
        return nil
    }

    private var target: String {
        model.writeTarget(for: option, choice: selection.isEmpty ? model.defaultTarget : selection)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(SettingsModel.label(for: option.key)).font(.headline)
                    Text(option.key).font(.caption.monospaced()).foregroundStyle(.secondary)
                }
                Spacer()
                if let file = Self.resetFile(for: option) {
                    Button("Reset") { _ = save(GHOSTTY_CONFIG_EDIT_UNSET, nil, file) }
                        .controlSize(.small)
                        .help("Remove from \(file)")
                }
                if option.kind != .keybind {
                    SourcePicker(files: model.files, selection: $selection)
                }
            }

            SettingsControl(model: model, option: option, save: save)

            if let error {
                Text(error).font(.caption).foregroundStyle(.red)
            }
            if option.kind != .keybind, let warning = model.overrideWarning(option: option, target: target) {
                Text(warning).font(.caption).foregroundStyle(.orange)
            }
            if case .theme(let path) = option.source {
                Text("theme: \((path as NSString).lastPathComponent)").font(.caption).foregroundStyle(.secondary)
            }

            HelpText(help: option.help)
        }
        .padding(.vertical, 4)
        .onChange(of: option.source) { selection = SourcePicker.resynced(selection, to: $0) }
    }

    private func save(_ op: ghostty_config_edit_op_e, _ value: String?, _ file: String?) -> Bool {
        switch model.apply(op, key: option.key, value: value, target: file ?? target) {
        case .ok:
            error = nil
            return true
        case .failed(let message):
            error = message
            return false
        }
    }
}

/// The first paragraph of help, with the rest behind "More".
/// A plain button, since DisclosureGroup hides its arrow inside a List row.
struct HelpText: View {
    let help: String
    @State private var expanded = false

    struct Parts: Equatable {
        let first: String
        let rest: String?
    }

    static func split(_ help: String) -> Parts {
        let paragraphs = help.components(separatedBy: "\n\n")
        let rest = paragraphs.dropFirst().joined(separator: "\n\n")
        return Parts(first: paragraphs.first ?? "", rest: rest.isEmpty ? nil : rest)
    }

    var body: some View {
        let parts = Self.split(help)
        if !parts.first.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Text(parts.first).font(.callout).foregroundStyle(.secondary)
                if let rest = parts.rest {
                    Button {
                        expanded.toggle()
                    } label: {
                        Label(expanded ? "Less" : "More", systemImage: expanded ? "chevron.down" : "chevron.right")
                            .font(.callout)
                    }
                    .buttonStyle(.link)
                    if expanded {
                        Text(rest)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }
}

/// The editor for an option, chosen by its kind. `save` takes an op, a value and
/// an explicit file (nil for the row's write target), and returns whether it saved.
private struct SettingsControl: View {
    @ObservedObject var model: SettingsModel
    let option: SettingsOption
    let save: (ghostty_config_edit_op_e, String?, String?) -> Bool

    @State private var text = ""
    @State private var newEntry = ""
    @State private var color = Color.clear
    @State private var colorWrite = Debounce()

    private var isUnset: Bool { option.source == .default }
    private var current: String { option.values.first ?? option.defaults.first ?? "" }

    var body: some View {
        Group {
            switch option.kind {
            case .bool:
                Toggle("", isOn: Binding(
                    get: { current == "true" },
                    set: { _ = save(GHOSTTY_CONFIG_EDIT_SET, $0 ? "true" : "false", nil) }))
                .toggleStyle(.switch)
                .opacity(isUnset ? 0.5 : 1)

            case .enum:
                Picker("", selection: Binding(
                    get: { current },
                    set: { if $0 != current { _ = save(GHOSTTY_CONFIG_EDIT_SET, $0, nil) } })) {
                    if !option.enumValues.contains(current) { Text(current).tag(current) }
                    ForEach(option.enumValues, id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.menu)
                .fixedSize()
                .opacity(isUnset ? 0.5 : 1)

            case .color:
                ColorPicker("", selection: colorBinding, supportsOpacity: false)
                    .opacity(isUnset ? 0.5 : 1)

            case .repeatable:
                repeatable

            case .keybind:
                Button("Edit in Keyboard Shortcuts") { model.select(section: .keybindings) }

            case .flags:
                FlagsControl(names: option.enumValues, current: current) {
                    _ = save(GHOSTTY_CONFIG_EDIT_SET, $0, nil)
                }
                .opacity(isUnset ? 0.5 : 1)

            case .int, .float, .string, .path, .other:
                HStack {
                    if let suggestions = Self.suggestions(for: option.key) {
                        SuggestionField(
                            text: $text, placeholder: option.defaults.first ?? "",
                            suggestions: suggestions, onCommit: submit)
                    } else {
                        TextField(option.defaults.first ?? "", text: $text)
                            .textFieldStyle(.roundedBorder)
                            .font(.body.monospaced())
                            .onSubmit(submit)
                    }
                    if Self.choosesFile(option.key) {
                        Button("Choose…") {
                            Self.chooseFile { text = $0; submit() }
                        }
                    }
                }
            }
        }
        .labelsHidden()
        .onAppear(perform: resetText)
        .onChange(of: option.values) { _ in resetText() }
    }

    /// Values to suggest while typing, for options with a known set.
    static func suggestions(for key: String) -> [Suggestion]? {
        switch key {
        case "command", "initial-command":
            Shells.installed.map { Suggestion(value: $0, section: nil, fontName: nil) }
        default: nil
        }
    }

    /// Options whose value is a file the user picks.
    static func choosesFile(_ key: String) -> Bool {
        ["background-image", "custom-shader"].contains(key)
    }

    private static func chooseFile(_ chosen: (String) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { chosen(url.path) }
    }

    /// Unset options show their default as the placeholder.
    private func resetText() {
        text = isUnset ? "" : current
        color = Color(nsColor: NSColor(hex: current) ?? .clear)
    }

    private func submit() {
        if text.isEmpty {
            if !isUnset { _ = save(GHOSTTY_CONFIG_EDIT_UNSET, nil, nil) }
        } else if isUnset || text != current {
            _ = save(GHOSTTY_CONFIG_EDIT_SET, text, nil)
        }
    }

    /// The picker edits a local draft; only the write is debounced.
    private var colorBinding: Binding<Color> {
        Binding(
            get: { color },
            set: { newColor in
                color = newColor
                guard let hex = Self.hex(NSColor(newColor)) else { return }
                colorWrite.run {
                    if hex.caseInsensitiveCompare(current) != .orderedSame {
                        _ = save(GHOSTTY_CONFIG_EDIT_SET, hex, nil)
                    }
                }
            })
    }

    private static func hex(_ color: NSColor) -> String? {
        guard let c = color.usingColorSpace(.sRGB) else { return nil }
        let rgb = [c.redComponent, c.greenComponent, c.blueComponent].map { Int((min(max($0, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", rgb[0], rgb[1], rgb[2])
    }

    @ViewBuilder
    private var repeatable: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(option.values.enumerated()), id: \.offset) { i, value in
                // `.other` entries can't be matched to a line, so they can't be removed either.
                let source = option.entrySource(i)
                let file = entryFile(source)
                HStack {
                    Text(value).font(.body.monospaced()).textSelection(.enabled)
                    Spacer()
                    Button("−") { _ = save(GHOSTTY_CONFIG_EDIT_REMOVE, value, file) }
                        .disabled(file == nil)
                        .help(file.map { "Remove from \($0)" } ?? (source == .other
                            ? "Set in a config file in a different form"
                            : "Set by default; can't be removed"))
                }
                .foregroundStyle(file == nil && source != .other ? .secondary : .primary)
            }
            HStack {
                TextField("Add entry", text: $newEntry)
                    .textFieldStyle(.roundedBorder)
                    .font(.body.monospaced())
                    .onSubmit(add)
                Button("+", action: add).disabled(newEntry.isEmpty)
                if Self.choosesFile(option.key) {
                    Button("Choose…") {
                        Self.chooseFile { newEntry = $0; add() }
                    }
                }
            }
        }
    }

    private func entryFile(_ source: SettingsSource) -> String? {
        if case .file(let path, _) = source { return path }
        return nil
    }

    private func add() {
        guard !newEntry.isEmpty else { return }
        if save(GHOSTTY_CONFIG_EDIT_ADD, newEntry, nil) { newEntry = "" }
    }
}

/// Runs only the last of a burst of calls. A class so rescheduling doesn't redraw.
private final class Debounce {
    private var task: Task<Void, Never>?

    @MainActor func run(after nanoseconds: UInt64 = 300_000_000, _ body: @escaping @MainActor () -> Void) {
        task?.cancel()
        task = Task { @MainActor in
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard !Task.isCancelled else { return }
            body()
        }
    }
}
