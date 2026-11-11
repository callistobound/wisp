import AppKit
import SwiftUI

/// Picks which file a row writes to. "" is "default", the default write target.
///
/// Drawn with plain SwiftUI rather than native controls: a list of these is laid out
/// all at once, and a native segmented control per row made the window slow to open.
struct SourcePicker: View {
    let files: [String]
    @Binding var selection: String
    @Environment(\.sourcePickerCompact) private var compact

    /// The initial selection for an option: its source file, or "default".
    static func initial(for source: SettingsSource) -> String {
        if case .file(let path, _) = source { return path }
        return ""
    }

    /// Follows a new source only while the selection is still "default".
    static func resynced(_ selection: String, to source: SettingsSource) -> String {
        selection.isEmpty ? initial(for: source) : selection
    }

    /// Width the segmented form needs for these files.
    static func segmentedWidth(files: [String]) -> CGFloat {
        let font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        return ([""] + files).reduce(0) { sum, choice in
            sum + (name(choice) as NSString).size(withAttributes: [.font: font]).width + segmentPadding * 2
        }
    }

    /// Whether a list this wide should show the compact menu instead of segments.
    static func isCompact(width: CGFloat, files: [String]) -> Bool {
        width < segmentedWidth(files: files) + labelReserve
    }

    private static let segmentPadding: CGFloat = 8
    /// Room left for the row's label and the list's insets.
    private static let labelReserve: CGFloat = 320

    private var choices: [String] {
        var out = [""] + files
        if !out.contains(selection) { out.append(selection) }
        return out
    }

    private static func name(_ choice: String) -> String {
        choice.isEmpty ? "default" : (choice as NSString).lastPathComponent
    }

    var body: some View {
        Group {
            if compact {
                Menu(Self.name(selection)) {
                    ForEach(choices, id: \.self) { choice in
                        Button(Self.name(choice)) { selection = choice }
                    }
                }
                .fixedSize()
            } else {
                segments
            }
        }
        .help(selection.isEmpty ? "Writes to the default config file" : selection)
    }

    private var segments: some View {
        HStack(spacing: 0) {
            ForEach(choices, id: \.self) { choice in
                let selected = choice == selection
                Text(Self.name(choice))
                    .padding(.horizontal, Self.segmentPadding)
                    .padding(.vertical, 2)
                    .foregroundStyle(selected ? Color.white : Color.primary)
                    .background(selected ? Color.accentColor : Color.clear)
                    .contentShape(Rectangle())
                    .onTapGesture { selection = choice }
                    .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
                    .help(choice.isEmpty ? "Writes to the default config file" : choice)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.secondary.opacity(0.5)))
        .fixedSize()
    }
}

private struct SourcePickerCompactKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Set once per list from its width, so rows don't each measure both forms.
    var sourcePickerCompact: Bool {
        get { self[SourcePickerCompactKey.self] }
        set { self[SourcePickerCompactKey.self] = newValue }
    }
}
