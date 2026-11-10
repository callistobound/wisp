import SwiftUI

/// Picks which file a row writes to. "" is "default", the default write target.
struct SourcePicker: View {
    let files: [String]
    @Binding var selection: String

    /// The initial selection for an option: its source file, or "default".
    static func initial(for source: SettingsSource) -> String {
        if case .file(let path, _) = source { return path }
        return ""
    }

    /// Follows a new source only while the selection is still "default".
    static func resynced(_ selection: String, to source: SettingsSource) -> String {
        selection.isEmpty ? initial(for: source) : selection
    }

    private var choices: [String] {
        var out = [""] + files
        if !out.contains(selection) { out.append(selection) }
        return out
    }

    private static func name(_ choice: String) -> String {
        choice.isEmpty ? "default" : (choice as NSString).lastPathComponent
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            Picker("Source", selection: $selection) {
                ForEach(choices, id: \.self) { Text(Self.name($0)).tag($0).help($0) }
            }
            .pickerStyle(.segmented)
            .fixedSize()

            Menu(Self.name(selection)) {
                ForEach(choices, id: \.self) { choice in
                    Button(Self.name(choice)) { selection = choice }
                }
            }
            .fixedSize()
        }
        .labelsHidden()
        .help(selection.isEmpty ? "Writes to the default config file" : selection)
    }
}
