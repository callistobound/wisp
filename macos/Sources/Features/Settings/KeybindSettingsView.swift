import SwiftUI
import GhosttyKit

/// One row per action, with a chip per trigger. List content, so search
/// results can show it beside settings.
struct KeybindSettingsView: View {
    @ObservedObject var model: SettingsModel
    /// Shows only actions containing this; empty shows all.
    var query = ""
    /// The action being recorded; one recorder at a time.
    @State private var recording: String?

    struct Chip: Identifiable, Equatable {
        /// The whole entry, "trigger=action".
        let value: String
        let trigger: String
        let source: SettingsSource
        /// Followed by `chain=` entries, which attach to whatever binding precedes them.
        var chained = false
        var id: String { value }
        var isDefault: Bool { source == .default }
    }

    struct Row: Identifiable {
        let action: String
        let chips: [Chip]
        var id: String { action }
    }

    /// Rows for every action in `values`, `defaults` or `enumValues`, sorted by action.
    static func rows(_ option: SettingsOption) -> [Row] {
        var chips: [String: [Chip]] = [:]
        for (i, value) in option.values.enumerated() {
            guard let (trigger, action) = Shortcut.split(binding: value), trigger != "chain" else { continue }
            let chained = option.values.indices.contains(i + 1) && option.values[i + 1].hasPrefix("chain=")
            chips[action, default: []].append(
                Chip(value: value, trigger: trigger, source: option.entrySource(i), chained: chained))
        }
        for value in option.defaults {
            guard let (trigger, action) = Shortcut.split(binding: value), trigger != "chain" else { continue }
            if chips[action] == nil { chips[action] = [] }
        }
        for action in option.enumValues where chips[action] == nil { chips[action] = [] }
        return chips.sorted { $0.key < $1.key }.map { Row(action: $0.key, chips: $0.value) }
    }

    static func filter(_ rows: [Row], query: String) -> [Row] {
        let query = query.trimmingCharacters(in: .whitespaces)
        return query.isEmpty ? rows : rows.filter { $0.action.localizedCaseInsensitiveContains(query) }
    }

    /// File-set chips are removed from their file. Defaults, chained heads and lines
    /// written in another form are unbound in `target`. Theme and CLI chips can't be removed.
    static func removal(of chip: Chip, target: String) -> (op: ghostty_config_edit_op_e, value: String, file: String)? {
        switch chip.source {
        case .file(let path, _) where !chip.chained: (GHOSTTY_CONFIG_EDIT_REMOVE, chip.value, path)
        case .file, .default, .other: (GHOSTTY_CONFIG_EDIT_ADD, "\(chip.trigger)=unbind", target)
        case .theme, .cli: nil
        }
    }

    var body: some View {
        if let option = model.options.first(where: { $0.key == "keybind" }) {
            let rows = Self.rows(option)
            ForEach(Self.filter(rows, query: query)) { row in
                KeybindRowView(model: model, row: row, recording: $recording) { trigger in
                    let shown = Shortcut.display(trigger)
                    return rows.first { other in
                        other.action != row.action && other.chips.contains { Shortcut.display($0.trigger) == shown }
                    }?.action
                }
            }
        } else {
            Text("No keybindings available.").foregroundStyle(.secondary)
        }
    }
}

private struct KeybindRowView: View {
    @ObservedObject var model: SettingsModel
    let row: KeybindSettingsView.Row
    @Binding var recordingAction: String?
    /// The other action already using a trigger, if any.
    let usedBy: (String) -> String?

    @State private var selection: String
    @State private var captured: String?
    @State private var held: NSEvent.ModifierFlags = []
    @State private var error: String?

    init(
        model: SettingsModel,
        row: KeybindSettingsView.Row,
        recording: Binding<String?>,
        usedBy: @escaping (String) -> String?
    ) {
        self.model = model
        self.row = row
        _recordingAction = recording
        self.usedBy = usedBy
        _selection = State(initialValue: SourcePicker.initial(for: Self.fileSource(row)))
    }

    /// The source of the row's last file-set chip, or default.
    private static func fileSource(_ row: KeybindSettingsView.Row) -> SettingsSource {
        row.chips.last { if case .file = $0.source { true } else { false } }?.source ?? .default
    }

    private var target: String { selection.isEmpty ? model.defaultTarget : selection }
    private var recording: Bool { recordingAction == row.action }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(row.action).font(.body.monospaced()).textSelection(.enabled)
                Spacer()
                SourcePicker(files: model.files, selection: $selection)
            }

            HStack(spacing: 6) {
                ForEach(row.chips) { chip in
                    ChipView(chip: chip, remove: KeybindSettingsView.removal(of: chip, target: target).map { e in
                        { _ = edit(e) }
                    })
                }
                if !recording {
                    Button("Record") {
                        captured = nil
                        held = []
                        recordingAction = row.action
                    }
                }
            }

            if recording { recorder }

            if let error {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        }
        .padding(.vertical, 4)
        .onChange(of: Self.fileSource(row)) { selection = SourcePicker.resynced(selection, to: $0) }
    }

    @ViewBuilder
    private var recorder: some View {
        HStack {
            ZStack {
                ShortcutRecorder(onModifiers: { held = $0 }, onCapture: { captured = $0 }, onCancel: stopRecording)
                Text(captured.map(Shortcut.display) ?? (held.isEmpty ? "Type a shortcut…" : Shortcut.symbols(held)))
                    .foregroundStyle(captured == nil ? .secondary : .primary)
                    .allowsHitTesting(false)
            }
            .frame(width: 180, height: 22)
            .background(RoundedRectangle(cornerRadius: 5).stroke(Color.accentColor))

            Button("Accept") {
                guard let captured else { return }
                if edit((GHOSTTY_CONFIG_EDIT_ADD, "\(captured)=\(row.action)", target)) { stopRecording() }
            }
            .disabled(captured == nil)
            Button("Cancel", action: stopRecording)
        }
        if let captured, let other = usedBy(captured) {
            Text("⚠ \(Shortcut.display(captured)) is already used by \(other).")
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }

    private func stopRecording() {
        if recording { recordingAction = nil }
        captured = nil
        held = []
    }

    @discardableResult
    private func edit(_ e: (op: ghostty_config_edit_op_e, value: String, file: String)) -> Bool {
        switch model.apply(e.op, key: "keybind", value: e.value, target: e.file) {
        case .ok:
            error = nil
            return true
        case .failed(let message):
            error = message
            return false
        }
    }
}

private struct ChipView: View {
    let chip: KeybindSettingsView.Chip
    /// Nil when the chip can't be removed.
    let remove: (() -> Void)?

    private var help: String {
        switch chip.source {
        case .file(let path, let line): "\(chip.value) (\(path):\(line))"
        case .default: "\(chip.value) (default)"
        case .theme(let path): "\(chip.value). Set by theme \((path as NSString).lastPathComponent)"
        case .cli: "\(chip.value). Set on the command line"
        case .other: "\(chip.value). Set in a config file in a different form"
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            Text(Shortcut.display(chip.trigger))
            if let remove {
                Button(action: remove) {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .help(chip.isDefault ? "Unbind this default" : "Remove")
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .foregroundStyle(chip.isDefault ? .secondary : .primary)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: chip.isDefault ? [3] : []))
                .foregroundStyle(.secondary))
        .help(help)
    }
}
