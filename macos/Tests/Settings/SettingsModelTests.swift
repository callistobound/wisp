import Foundation
import Testing
@testable import Ghostty
@testable import GhosttyKit

@Suite
@MainActor
struct SettingsModelTests {
    private func option(_ key: String, source: SettingsSource = .default, help: String = "") -> SettingsOption {
        SettingsOption(
            key: key, kind: .string, help: help, enumValues: [],
            values: [], defaults: [], source: source, entrySources: [])
    }

    private func model(files: [String] = [], options: [SettingsOption] = []) throws -> SettingsModel {
        let model = SettingsModel(config: try TemporaryConfig(""), defaultTarget: "/default")
        model.files = files
        model.options = options
        return model
    }

    // MARK: - Labels and sections

    @Test func labelCapitalizesFirstWord() {
        #expect(SettingsModel.label(for: "font-size") == "Font size")
    }

    @Test func labelKeepsAcronyms() {
        #expect(SettingsModel.label(for: "macos-titlebar-style") == "macOS titlebar style")
    }

    @Test func sectionByPrefix() {
        #expect(SettingsModel.section(for: "font-family") == .font)
        #expect(SettingsModel.section(for: "keybind") == .keybindings)
        #expect(SettingsModel.section(for: "unknown-thing") == .advanced)
    }

    // MARK: - Write targets

    @Test func writeTargetChoiceWins() throws {
        let m = try model()
        let opt = option("font-size", source: .file(path: "/a", line: 1))
        #expect(m.writeTarget(for: opt, choice: "/b") == "/b")
    }

    @Test func writeTargetUsesFileSource() throws {
        let m = try model()
        let opt = option("font-size", source: .file(path: "/a", line: 1))
        #expect(m.writeTarget(for: opt, choice: nil) == "/a")
    }

    @Test func writeTargetDefaultUsesDefaultTarget() throws {
        let m = try model()
        #expect(m.writeTarget(for: option("font-size"), choice: nil) == "/default")
    }

    @Test func writeTargetThemeUsesDefaultTarget() throws {
        let m = try model()
        let opt = option("background", source: .theme(path: "/themes/x"))
        #expect(m.writeTarget(for: opt, choice: nil) == "/default")
    }

    // MARK: - Override warning

    @Test func overrideWarningWhenTargetLoadsEarlier() throws {
        let m = try model(files: ["/c/a", "/c/b"])
        let opt = option("font-size", source: .file(path: "/c/b", line: 3))
        #expect(m.overrideWarning(option: opt, target: "/c/a") == "⚠ b sets this later and will override it.")
        #expect(m.overrideWarning(option: opt, target: "/c/b") == nil)
    }

    @Test func overrideWarningWhenTargetNotLoaded() throws {
        let m = try model(files: ["/c/b"])
        let opt = option("font-size", source: .file(path: "/c/b", line: 3))
        #expect(m.overrideWarning(option: opt, target: "/c/new") == "⚠ b sets this later and will override it.")
        #expect(m.overrideWarning(option: option("font-size"), target: "/c/new") == nil)
    }

    @Test func overrideWarningNormalizesPaths() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("config").path
        let link = dir.appendingPathComponent("link").path
        try "".write(toFile: file, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: file)

        let m = try model(files: [file])
        let opt = option("font-size", source: .file(path: file, line: 1))
        #expect(m.overrideWarning(option: opt, target: dir.appendingPathComponent("sub/../config").path) == nil)
        #expect(m.overrideWarning(option: opt, target: link) == nil)
    }

    // MARK: - Filtering

    @Test func searchMatchesKeyAndIgnoresSection() throws {
        let m = try model(options: [option("window-padding-x"), option("font-size")])
        m.selectedSection = .font
        m.search = "PADDING"
        #expect(m.visibleOptions.map(\.key) == ["window-padding-x"])
    }

    // MARK: - Integration

    @Test func reloadClearsMissingSelectedFile() throws {
        let m = try model()
        m.selectedFile = "/gone"
        m.reload(config: try TemporaryConfig(""))
        #expect(m.selectedFile == nil)
    }

    @Test func fileSourceFromConfig() throws {
        let config = try TemporaryConfig("font-size = 15\n")
        let m = SettingsModel(config: config, defaultTarget: config.temporaryFile.path())
        let opt = try #require(m.options.first { $0.key == "font-size" })
        #expect(opt.source == .file(path: config.temporaryFile.path(), line: 1))
        #expect(opt.values == ["15"])
        #expect(m.files == [config.temporaryFile.path()])
    }

    @Test func applySetWritesFile() throws {
        let config = try TemporaryConfig("font-size = 15\n")
        let path = config.temporaryFile.path()
        var saved = 0
        let m = SettingsModel(config: config, defaultTarget: path, onSaved: { saved += 1 })
        #expect(m.apply(GHOSTTY_CONFIG_EDIT_SET, key: "font-size", value: "16", target: path) == .ok)
        #expect(try String(contentsOfFile: path, encoding: .utf8) == "font-size = 16\n")
        #expect(saved == 1)
    }

    @Test func applyInvalidValueLeavesFile() throws {
        let config = try TemporaryConfig("font-size = 15\n")
        let path = config.temporaryFile.path()
        var saved = 0
        let m = SettingsModel(config: config, defaultTarget: path, onSaved: { saved += 1 })
        let result = m.apply(GHOSTTY_CONFIG_EDIT_SET, key: "font-size", value: "abc", target: path)
        #expect(result == .failed("Invalid value for font-size"))
        #expect(try String(contentsOfFile: path, encoding: .utf8) == "font-size = 15\n")
        #expect(saved == 0)
    }

    // MARK: - Reset

    @Test func resetFileOnlyForFileSources() {
        #expect(SettingsRowView.resetFile(for: option("a", source: .file(path: "/a", line: 1))) == "/a")
        #expect(SettingsRowView.resetFile(for: option("a")) == nil)
        #expect(SettingsRowView.resetFile(for: option("a", source: .theme(path: "/t"))) == nil)
        #expect(SettingsRowView.resetFile(for: option("a", source: .cli)) == nil)
        #expect(SettingsRowView.resetFile(for: option("a", source: .other)) == nil)
        let keybind = SettingsOption(
            key: "keybind", kind: .keybind, help: "", enumValues: [],
            values: [], defaults: [], source: .file(path: "/a", line: 1), entrySources: [])
        #expect(SettingsRowView.resetFile(for: keybind) == nil)
    }

    @Test func resetUnsetsTheLine() throws {
        let config = try TemporaryConfig("window-inherit-font-size = false\n")
        let path = config.temporaryFile.path()
        let m = SettingsModel(config: config, defaultTarget: path)
        let opt = try #require(m.options.first { $0.key == "window-inherit-font-size" })
        let file = try #require(SettingsRowView.resetFile(for: opt))
        #expect(m.apply(GHOSTTY_CONFIG_EDIT_UNSET, key: opt.key, value: nil, target: file) == .ok)
        #expect(try String(contentsOfFile: path, encoding: .utf8) == "")
        try config.reload(nil)
        m.reload(config: config)
        #expect(m.options.first { $0.key == "window-inherit-font-size" }?.source == .default)
    }

    // MARK: - Entry sources

    @Test func entryNotInFileOrDefaultsIsOther() {
        let opt = SettingsOption(
            key: "config-file", kind: .repeatable, help: "", enumValues: [],
            values: ["/abs/a", "/abs/b", "/abs/c"], defaults: ["/abs/b"], source: .default,
            entrySources: [.default, .default, .file(path: "/f", line: 2)])
        #expect(opt.entrySource(0) == .other)
        #expect(opt.entrySource(1) == .default)
        #expect(opt.entrySource(2) == .file(path: "/f", line: 2))
    }

    // MARK: - Source picker

    @Test func pickerResyncsOnlyFromDefault() {
        #expect(SourcePicker.resynced("", to: .file(path: "/a", line: 1)) == "/a")
        #expect(SourcePicker.resynced("/b", to: .file(path: "/a", line: 1)) == "/b")
        #expect(SourcePicker.resynced("", to: .default) == "")
    }
}
