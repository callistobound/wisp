import AppKit

/// The colors a theme file sets, for previews.
struct ThemeColors {
    let background: NSColor
    let foreground: NSColor
    let palette: [Int: NSColor]

    /// By the background's relative luminance.
    var isDark: Bool {
        guard let c = background.usingColorSpace(.sRGB) else { return true }
        func linear(_ v: CGFloat) -> CGFloat { v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(c.redComponent) + 0.7152 * linear(c.greenComponent) + 0.0722 * linear(c.blueComponent) < 0.5
    }

    /// Reads `background`, `foreground` and `palette = N=#hex`; nil without a background.
    static func parse(_ text: String) -> ThemeColors? {
        var background: NSColor?
        var foreground: NSColor = .textColor
        var palette: [Int: NSColor] = [:]
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2 else { continue }
            switch parts[0] {
            case "background": background = NSColor(hex: parts[1])
            case "foreground": foreground = NSColor(hex: parts[1]) ?? foreground
            case "palette":
                let entry = parts[1].split(separator: "=", maxSplits: 1)
                if entry.count == 2, let index = Int(entry[0]), let color = NSColor(hex: String(entry[1])) {
                    palette[index] = color
                }
            default: break
            }
        }
        guard let background else { return nil }
        return ThemeColors(background: background, foreground: foreground, palette: palette)
    }
}

/// A `theme` value: one name, or `light:X,dark:Y`.
struct ThemeValue: Equatable {
    var light: String
    var dark: String
    var isSplit: Bool

    init(_ text: String) {
        var light: String?
        var dark: String?
        for part in text.split(separator: ",") {
            let pair = part.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if pair.count == 2, pair[0] == "light" { light = pair[1] }
            if pair.count == 2, pair[0] == "dark" { dark = pair[1] }
        }
        if let light, let dark {
            self.light = light
            self.dark = dark
            isSplit = true
        } else {
            let name = text.trimmingCharacters(in: .whitespaces)
            self.light = name
            self.dark = name
            isSplit = false
        }
    }

    var text: String { isSplit ? "light:\(light),dark:\(dark)" : light }
}

/// Theme names and colors from the bundled themes and the user's themes directory.
@MainActor
enum ThemeCatalog {
    private static var cache: [URL: ThemeColors?] = [:]

    /// The bundled themes, then `themes` next to the main config (which win).
    static func directories(mainConfig: String) -> [URL] {
        var dirs: [URL] = []
        if let resources = Bundle.main.resourceURL {
            dirs.append(resources.appendingPathComponent("ghostty/themes"))
        }
        dirs.append(URL(fileURLWithPath: mainConfig).deletingLastPathComponent().appendingPathComponent("themes"))
        return dirs
    }

    /// File names across `directories`, sorted case-insensitively.
    nonisolated static func names(in directories: [URL]) -> [String] {
        var names = Set<String>()
        for dir in directories {
            let files = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
            names.formUnion(files.filter { !$0.hasPrefix(".") })
        }
        return names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// The named theme's colors, from the last directory that has it.
    static func colors(named name: String, in directories: [URL]) -> ThemeColors? {
        guard let url = directories.reversed().map({ $0.appendingPathComponent(name) })
            .first(where: { FileManager.default.fileExists(atPath: $0.path) }) else { return nil }
        if let cached = cache[url] { return cached }
        let colors = (try? String(contentsOf: url, encoding: .utf8)).flatMap(ThemeColors.parse)
        cache[url] = colors
        return colors
    }
}
