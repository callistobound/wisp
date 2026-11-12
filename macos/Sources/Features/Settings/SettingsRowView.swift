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
    @State private var choosingTheme = false

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
                    if let suggestions = suggestions(for: option.key) {
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
                    if option.key == "theme" {
                        Button("Choose…") { choosingTheme = true }
                            .sheet(isPresented: $choosingTheme) {
                                ThemePicker(current: current, directories: themeDirectories) {
                                    text = $0
                                    _ = save(GHOSTTY_CONFIG_EDIT_SET, $0, nil)
                                }
                            }
                    }
                }
            }
        }
        .labelsHidden()
        .onAppear { resetText(option) }
        // The new option, since the closure sees the view from before the change.
        .onChange(of: option) { resetText($0) }
    }

    private var themeDirectories: [URL] { ThemeCatalog.directories(mainConfig: model.defaultTarget) }

    /// Values to suggest while typing, for options with a known set.
    private func suggestions(for key: String) -> [Suggestion]? {
        switch key {
        case "command", "initial-command":
            Shells.installed.map { Suggestion(value: $0, section: nil, fontName: nil) }
        case "theme":
            ThemeCatalog.cachedNames(in: themeDirectories).map { Suggestion(value: $0, section: nil, fontName: nil) }
        case _ where key.hasPrefix("font-family"):
            FontCatalog.families()
        case _ where key.hasPrefix("font-style"):
            family.map { FontCatalog.styles(family: $0).map { Suggestion(value: $0, section: nil, fontName: nil) } }
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
    private func resetText(_ option: SettingsOption) {
        let current = option.values.first ?? option.defaults.first ?? ""
        text = option.source == .default ? "" : current
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
                if let suggestions = suggestions(for: option.key) {
                    SuggestionField(text: $newEntry, placeholder: "Add entry", suggestions: suggestions, onCommit: add)
                } else {
                    TextField("Add entry", text: $newEntry)
                        .textFieldStyle(.roundedBorder)
                        .font(.body.monospaced())
                        .onSubmit(add)
                }
                Button("+", action: add).disabled(newEntry.isEmpty)
                if Self.choosesFile(option.key) {
                    Button("Choose…") {
                        Self.chooseFile { newEntry = $0; add() }
                    }
                }
            }
            if option.key == "font-feature", let family {
                fontFeatures(family)
            }
            if option.key.hasPrefix("font-variation"), let family {
                let axes = FontCatalog.axes(family: family)
                if !axes.isEmpty {
                    Text(axes.map { "\($0.tag) (\($0.name)) \(Self.number($0.min))–\(Self.number($0.max))" }
                        .joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    /// The family this font option applies to, if it's a font option.
    private var family: String? {
        guard option.key.hasPrefix("font-") else { return nil }
        let values = Dictionary(model.options.filter { $0.key.hasPrefix("font-family") }.map { ($0.key, $0.values) }) { a, _ in a }
        return FontCatalog.primaryFamily(option: option.key, values: values)
    }

    /// A checkbox per feature the family supports, showing whether it ends up on
    /// (some are on by default). Toggling removes single-feature entries for it from
    /// their files and adds `tag` or `-tag` to the row's file if still needed.
    @ViewBuilder
    private func fontFeatures(_ family: String) -> some View {
        let features = FontCatalog.features(family: family)
        if !features.isEmpty {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), alignment: .leading)], alignment: .leading) {
                ForEach(features, id: \.tag) { feature in
                    Toggle("\(feature.name) (\(feature.tag))", isOn: Binding(
                        get: { FontCatalog.featureIsOn(feature.tag, entries: option.values) },
                        set: { setFeature(feature.tag, on: $0) }))
                    .toggleStyle(.checkbox)
                }
            }
        }
    }

    private func setFeature(_ tag: String, on: Bool) {
        let edit = FontCatalog.featureEdit(tag, on: on, entries: option.values)
        for entry in edit.remove {
            guard let i = option.values.firstIndex(of: entry), let file = entryFile(option.entrySource(i)) else { continue }
            _ = save(GHOSTTY_CONFIG_EDIT_REMOVE, entry, file)
        }
        if let add = edit.add { _ = save(GHOSTTY_CONFIG_EDIT_ADD, add, nil) }
    }

    private static func number(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v)
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
