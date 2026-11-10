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
struct HelpText: View {
    let help: String

    var body: some View {
        let paragraphs = help.components(separatedBy: "\n\n")
        if let first = paragraphs.first, !first.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Text(first).font(.callout).foregroundStyle(.secondary)
                if paragraphs.count > 1 {
                    DisclosureGroup("More") {
                        Text(paragraphs.dropFirst().joined(separator: "\n\n"))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .font(.callout)
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
    @State private var colorTask: Task<Void, Never>?

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
                    set: { _ = save(GHOSTTY_CONFIG_EDIT_SET, $0, nil) })) {
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
                Button("Edit in Keyboard Shortcuts") {
                    model.search = ""
                    model.selectedFile = nil
                    model.selectedSection = .keybindings
                }

            case .int, .float, .string, .path, .other:
                TextField(option.defaults.first ?? "", text: $text)
                    .textFieldStyle(.roundedBorder)
                    .font(.body.monospaced())
                    .onSubmit {
                        if text.isEmpty {
                            _ = save(GHOSTTY_CONFIG_EDIT_UNSET, nil, nil)
                        } else {
                            _ = save(GHOSTTY_CONFIG_EDIT_SET, text, nil)
                        }
                    }
            }
        }
        .labelsHidden()
        .onAppear(perform: resetText)
        .onChange(of: option.values) { _ in resetText() }
    }

    /// Unset options show their default as the placeholder.
    private func resetText() {
        text = isUnset ? "" : current
    }

    private var colorBinding: Binding<Color> {
        Binding(
            get: { Color(nsColor: NSColor(hex: current) ?? .clear) },
            set: { color in
                guard let hex = Self.hex(NSColor(color)) else { return }
                // ColorPicker updates continuously while dragging.
                colorTask?.cancel()
                colorTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    guard !Task.isCancelled else { return }
                    _ = save(GHOSTTY_CONFIG_EDIT_SET, hex, nil)
                }
            })
    }

    private static func hex(_ color: NSColor) -> String? {
        guard let c = color.usingColorSpace(.sRGB) else { return nil }
        let rgb = [c.redComponent, c.greenComponent, c.blueComponent].map { Int(($0 * 255).rounded()) }
        return String(format: "#%02X%02X%02X", rgb[0], rgb[1], rgb[2])
    }

    @ViewBuilder
    private var repeatable: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(option.values.enumerated()), id: \.offset) { i, value in
                HStack {
                    Text(value).font(.body.monospaced()).textSelection(.enabled)
                    Spacer()
                    let file = entryFile(i)
                    Button("−") { _ = save(GHOSTTY_CONFIG_EDIT_REMOVE, value, file) }
                        .disabled(file == nil)
                        .help(file.map { "Remove from \($0)" } ?? "Set by default; can't be removed")
                }
                .foregroundStyle(entryFile(i) == nil ? .secondary : .primary)
            }
            HStack {
                TextField("Add entry", text: $newEntry)
                    .textFieldStyle(.roundedBorder)
                    .font(.body.monospaced())
                    .onSubmit(add)
                Button("+", action: add).disabled(newEntry.isEmpty)
            }
        }
    }

    private func entryFile(_ i: Int) -> String? {
        guard i < option.entrySources.count, case .file(let path, _) = option.entrySources[i] else { return nil }
        return path
    }

    private func add() {
        guard !newEntry.isEmpty else { return }
        if save(GHOSTTY_CONFIG_EDIT_ADD, newEntry, nil) { newEntry = "" }
    }
}
