import AppKit
import Carbon.HIToolbox
import Foundation
import Testing
@testable import Ghostty
@testable import GhosttyKit

@Suite
struct ShortcutTests {
    // MARK: - Display

    @Test func displayModsAndLetter() {
        #expect(Shortcut.display("ctrl+shift+a") == "⌃⇧A")
    }

    @Test func displayNamedKey() {
        #expect(Shortcut.display("super+comma") == "⌘,")
    }

    @Test func displaySequence() {
        #expect(Shortcut.display("ctrl+a>n") == "⌃A then N")
    }

    // MARK: - Trigger

    @Test func triggerCommandLetter() {
        #expect(Shortcut.trigger(keyCode: UInt16(kVK_ANSI_T), characters: "t", modifiers: [.command]) == "super+t")
    }

    @Test func triggerModifierOrder() {
        let t = Shortcut.trigger(keyCode: UInt16(kVK_ANSI_A), characters: "A", modifiers: [.shift, .control])
        #expect(t == "ctrl+shift+a")
    }

    @Test func triggerSuperFirst() {
        let t = Shortcut.trigger(keyCode: UInt16(kVK_ANSI_T), characters: "t", modifiers: [.control, .command])
        #expect(t == "super+ctrl+t")
    }

    @Test func displayEitherModifierOrder() {
        #expect(Shortcut.display("super+ctrl+t") == "⌃⌘T")
        #expect(Shortcut.display("ctrl+super+t") == "⌃⌘T")
    }

    @Test func triggerModifierOnly() {
        #expect(Shortcut.trigger(keyCode: UInt16(kVK_Shift), characters: nil, modifiers: [.shift]) == nil)
        #expect(Shortcut.trigger(keyCode: UInt16(kVK_Command), characters: "", modifiers: [.command]) == nil)
    }

    @Test func triggerNamedKeys() {
        #expect(Shortcut.trigger(keyCode: UInt16(kVK_UpArrow), characters: "\u{F700}", modifiers: []) == "arrow_up")
        #expect(Shortcut.trigger(keyCode: UInt16(kVK_ANSI_Equal), characters: "=", modifiers: [.command]) == "super+equal")
        #expect(Shortcut.trigger(keyCode: UInt16(kVK_Space), characters: " ", modifiers: [.option]) == "alt+space")
    }

    /// Every physical key name must be one Ghostty's trigger parser accepts.
    @Test func everyKeyNameParses() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        var count = 0
        for key in Ghostty.Input.Key.allCases {
            guard let code = key.keyCode,
                  let trigger = Shortcut.trigger(keyCode: code, characters: nil, modifiers: [.control]) else { continue }
            count += 1
            let value = "\(trigger)=ignore"
            let result = ghostty_config_edit(
                file.path, GHOSTTY_CONFIG_EDIT_ADD, "keybind", 7, value, UInt(value.utf8.count))
            #expect(result == GHOSTTY_CONFIG_EDIT_OK, "\(key) -> \(trigger)")
        }
        #expect(count > 100)
    }

    // MARK: - Keybind rows

    @Test func splitBinding() {
        #expect(Shortcut.split(binding: "super+t=new_tab")! == ("super+t", "new_tab"))
        #expect(Shortcut.split(binding: "ctrl+==ignore")! == ("ctrl+=", "ignore"))
        #expect(Shortcut.split(binding: "ctrl+a>n=goto_split:right")! == ("ctrl+a>n", "goto_split:right"))
        #expect(Shortcut.split(binding: "nothing") == nil)
    }

    @Test @MainActor func removeChipRemovesOnlyThatLine() throws {
        let config = try TemporaryConfig("keybind = ctrl+a=new_tab\nkeybind = ctrl+b=new_tab\n")
        let path = config.temporaryFile.path()
        let m = SettingsModel(config: config, defaultTarget: path)
        let option = try #require(m.options.first { $0.key == "keybind" })
        let row = try #require(KeybindSettingsView.rows(option).first { $0.action == "new_tab" })
        let chip = try #require(row.chips.first { $0.trigger == "ctrl+a" })
        #expect(chip.source == .file(path: path, line: 1))

        let edit = KeybindSettingsView.removal(of: chip, target: "/unused")
        #expect(edit.op == GHOSTTY_CONFIG_EDIT_REMOVE && edit.file == path)
        #expect(m.apply(edit.op, key: "keybind", value: edit.value, target: edit.file) == .ok)
        #expect(try String(contentsOfFile: path, encoding: .utf8) == "keybind = ctrl+b=new_tab\n")
    }

    @Test @MainActor func removeDefaultChipUnbinds() throws {
        let config = try TemporaryConfig("")
        let m = SettingsModel(config: config, defaultTarget: "/t")
        let option = try #require(m.options.first { $0.key == "keybind" })
        let rows = KeybindSettingsView.rows(option)
        let chip = try #require(rows.flatMap(\.chips).first)
        #expect(chip.isDefault)
        let edit = KeybindSettingsView.removal(of: chip, target: "/t")
        #expect(edit.op == GHOSTTY_CONFIG_EDIT_ADD && edit.file == "/t")
        #expect(edit.value == "\(chip.trigger)=unbind")
    }
}
