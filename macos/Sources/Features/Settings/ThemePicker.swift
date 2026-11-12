import SwiftUI

/// Picks a theme, or a light and a dark one, with previews in each theme's colors.
struct ThemePicker: View {
    let directories: [URL]
    let onUse: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    private enum Side: Hashable { case both, light, dark }

    @State private var value: ThemeValue
    @State private var side: Side
    @State private var search = ""
    private let names: [String]
    private let original: ThemeValue

    init(current: String, directories: [URL], onUse: @escaping (String) -> Void) {
        self.directories = directories
        self.onUse = onUse
        let value = ThemeValue(current)
        original = value
        names = ThemeCatalog.names(in: directories)
        _value = State(initialValue: value)
        _side = State(initialValue: value.isSplit ? .light : .both)
    }

    private var selected: String { side == .dark ? value.dark : value.light }

    private var shown: [String] {
        search.isEmpty ? names : names.filter { $0.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                TextField("Search \(names.count) themes", text: $search).textFieldStyle(.roundedBorder)
                Picker("", selection: $side) {
                    Text("Same for light and dark").tag(Side.both)
                    Text("Light").tag(Side.light)
                    Text("Dark").tag(Side.dark)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            List(shown, id: \.self) { name in
                ThemeRow(name: name, colors: ThemeCatalog.colors(named: name, in: directories),
                         isCurrent: name == original.light || name == original.dark,
                         isSelected: name == selected)
                    .contentShape(Rectangle())
                    .onTapGesture { choose(name) }
            }
            .listStyle(.plain)
            HStack {
                Text(value.text).font(.callout.monospaced()).foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Use \(value.isSplit ? "Themes" : value.light)") {
                    onUse(value.text)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(value.light.isEmpty)
            }
        }
        .padding(16)
        .frame(minWidth: 620, minHeight: 520)
        .onChange(of: side) { newSide in
            // Picking a side starts a split from the single theme.
            if newSide != .both { value.isSplit = true } else { value.isSplit = false; value.dark = value.light }
        }
    }

    private func choose(_ name: String) {
        switch side {
        case .both:
            value.light = name
            value.dark = name
        case .light: value.light = name
        case .dark: value.dark = name
        }
    }
}

private struct ThemeRow: View {
    let name: String
    let colors: ThemeColors?
    let isCurrent: Bool
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 14) {
            Text(name).fontWeight(.semibold).frame(width: 190, alignment: .leading)
            if let colors { ThemeTile(colors: colors) }
            Text([colors.map { $0.isDark ? "Dark" : "Light" }, isCurrent ? "current" : nil]
                .compactMap { $0 }.joined(separator: " · "))
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 8).fill(isSelected ? Color.accentColor.opacity(0.15) : .clear))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2))
    }
}

/// A sample prompt and palette swatches in the theme's colors.
private struct ThemeTile: View {
    let colors: ThemeColors

    private func color(_ index: Int) -> Color { Color(nsColor: colors.palette[index] ?? colors.foreground) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            (Text("~/src ") + Text("main ").foregroundColor(color(2)) + Text("❯ ").foregroundColor(color(4)) + Text("ls"))
                .foregroundColor(Color(nsColor: colors.foreground))
            HStack(spacing: 2) {
                ForEach([1, 2, 3, 4, 5, 6, 8], id: \.self) { i in
                    RoundedRectangle(cornerRadius: 2).fill(color(i)).frame(width: 12, height: 12)
                }
            }
        }
        .font(.system(size: 11.5, design: .monospaced))
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .frame(width: 230, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: colors.background)))
    }
}
