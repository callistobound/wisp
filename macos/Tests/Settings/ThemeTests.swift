import Foundation
import Testing
@testable import Ghostty

@Suite
struct ThemeTests {
    @Test func parsesThemeColors() throws {
        let colors = try #require(ThemeColors.parse("background = #f7f7f7\nforeground = #000000\npalette = 1=#aa3731\n"))
        #expect(!colors.isDark)
        #expect(colors.palette[1] != nil)
        #expect(colors.palette[2] == nil)
    }

    @Test func darkBackgroundIsDark() throws {
        #expect(try #require(ThemeColors.parse("background = #282a36\nforeground = #f8f8f2\n")).isDark)
    }

    @Test func noBackgroundIsNoTheme() {
        #expect(ThemeColors.parse("foreground = #000000\n") == nil)
    }

    @Test func themeValueSplit() {
        let value = ThemeValue("light:A,dark:B")
        #expect(value.isSplit && value.light == "A" && value.dark == "B")
        #expect(value.text == "light:A,dark:B")
        #expect(ThemeValue("dark:B,light:A").text == "light:A,dark:B")
    }

    @Test func themeValueSingle() {
        let value = ThemeValue("Alabaster")
        #expect(!value.isSplit && value.light == "Alabaster")
        #expect(value.text == "Alabaster")
    }

    @Test func namesMergeDirectories() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let a = root.appendingPathComponent("a"), b = root.appendingPathComponent("b")
        for (dir, files) in [(a, ["A", "B"]), (b, ["B", "c"])] {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            for f in files { try "background = #000000\n".write(to: dir.appendingPathComponent(f), atomically: true, encoding: .utf8) }
        }
        #expect(ThemeCatalog.names(in: [a, b]) == ["A", "B", "c"])
    }
}
