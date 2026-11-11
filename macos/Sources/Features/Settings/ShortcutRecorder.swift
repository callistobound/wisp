import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Pure helpers for converting key events to and from Ghostty trigger strings.
enum Shortcut {
    /// Printable characters that would confuse the trigger or config parser.
    private static let reserved: Set<Character> = ["=", "+", ">", ":", "#", "\""]

    private static let modifierKeys: Set<Ghostty.Input.Key> = [
        .shiftLeft, .shiftRight, .controlLeft, .controlRight, .altLeft, .altRight,
        .metaLeft, .metaRight, .capsLock, .fn,
    ]

    /// A trigger like "super+ctrl+a", or nil for a modifier-only press.
    static func trigger(keyCode: UInt16, characters: String?, modifiers: NSEvent.ModifierFlags) -> String? {
        let physical = Ghostty.Input.Key(keyCode: keyCode)
        if let physical, modifierKeys.contains(physical) { return nil }

        let name: String
        if let c = characters?.lowercased(), let ch = c.first, c.count == 1, isLiteral(ch) {
            name = c
        } else if let physical {
            name = ghosttyName(physical)
        } else {
            return nil
        }

        // Same order as Trigger.format, so entry sources and removal match.
        var mods = ""
        if modifiers.contains(.command) { mods += "super+" }
        if modifiers.contains(.control) { mods += "ctrl+" }
        if modifiers.contains(.option) { mods += "alt+" }
        if modifiers.contains(.shift) { mods += "shift+" }
        return mods + name
    }

    private static func isLiteral(_ ch: Character) -> Bool {
        guard !reserved.contains(ch), let s = ch.unicodeScalars.first else { return false }
        if s.isASCII { return s.value > 0x20 && s.value < 0x7f }
        return s.properties.isAlphabetic
    }

    /// The `src/input/key.zig` name: arrowUp -> arrow_up, digit0 -> digit_0, a -> key_a.
    static func ghosttyName(_ key: Ghostty.Input.Key) -> String {
        let raw = key.rawValue
        if raw.count == 1 { return "key_\(raw)" }
        let isFunction = raw.first == "f" && raw.dropFirst().allSatisfy(\.isNumber)
        var out = ""
        var prev: Character?
        for ch in raw {
            if ch.isUppercase {
                out += "_" + ch.lowercased()
            } else if ch.isNumber, !isFunction, prev?.isLetter == true {
                out += "_" + String(ch)
            } else {
                out.append(ch)
            }
            prev = ch
        }
        return out
    }

    /// "super+t=new_tab" -> ("super+t", "new_tab"). Like the parser, skips "=+" and "==".
    static func split(binding: String) -> (trigger: String, action: String)? {
        let chars = Array(binding)
        for i in chars.indices where chars[i] == "=" {
            if i + 1 < chars.count, chars[i + 1] == "+" || chars[i + 1] == "=" { continue }
            return (String(chars[..<i]), String(chars[(i + 1)...]))
        }
        return nil
    }

    // MARK: - Display

    static func symbols(_ modifiers: NSEvent.ModifierFlags) -> String {
        [(NSEvent.ModifierFlags.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")]
            .filter { modifiers.contains($0.0) }
            .map(\.1)
            .joined()
    }

    private static let flags = ["all:", "global:", "unconsumed:", "performable:"]

    private static let keySymbols: [String: String] = [
        "comma": ",", "period": ".", "minus": "-", "equal": "=", "slash": "/", "backslash": "\\",
        "semicolon": ";", "quote": "'", "backquote": "`", "bracket_left": "[", "bracket_right": "]",
        "arrow_up": "↑", "arrow_down": "↓", "arrow_left": "←", "arrow_right": "→",
        "enter": "↩", "tab": "⇥", "space": "Space", "backspace": "⌫", "delete": "⌦", "escape": "⎋",
        "home": "↖", "end": "↘", "page_up": "⇞", "page_down": "⇟",
    ]

    /// "global:super+a" -> (["global:"], "super+a").
    static func prefixes(_ trigger: String) -> (flags: [String], keys: String) {
        var t = Substring(trigger)
        var out: [String] = []
        while let flag = flags.first(where: { t.hasPrefix($0) }) {
            out.append(flag)
            t = t.dropFirst(flag.count)
        }
        return (out, String(t))
    }

    static func isGlobal(_ trigger: String) -> Bool {
        prefixes(trigger).flags.contains("global:")
    }

    /// "ctrl+shift+a" -> "⌃⇧A", "ctrl+a>n" -> "⌃A then N".
    static func display(_ trigger: String) -> String {
        prefixes(trigger).keys.split(separator: ">").map { chord(String($0)) }.joined(separator: " then ")
    }

    private static func chord(_ s: String) -> String {
        // A trailing "++" or a bare "+" is the literal plus key.
        var parts = s.split(separator: "+").map(String.init)
        if s == "+" || s.hasSuffix("++") { parts.append("+") }
        var mods = Set<String>()
        var key = ""
        for part in parts {
            switch part {
            case "ctrl", "control": mods.insert("⌃")
            case "alt", "opt", "option": mods.insert("⌥")
            case "shift": mods.insert("⇧")
            case "super", "cmd", "command": mods.insert("⌘")
            default: key = keyName(part)
            }
        }
        return ["⌃", "⌥", "⇧", "⌘"].filter(mods.contains).joined() + key
    }

    private static func keyName(_ name: String) -> String {
        if let symbol = keySymbols[name] { return symbol }
        if name.count == 1 { return name.uppercased() }
        if name.hasPrefix("key_") || name.hasPrefix("digit_") {
            return String(name.split(separator: "_").last ?? "").uppercased()
        }
        if name.first == "f", name.dropFirst().allSatisfy(\.isNumber) { return name.uppercased() }
        return name
    }
}

/// Captures one key chord while it has focus.
struct ShortcutRecorder: NSViewRepresentable {
    let onModifiers: (NSEvent.ModifierFlags) -> Void
    let onCapture: (String) -> Void
    /// Escape with no modifiers.
    let onCancel: () -> Void

    func makeNSView(context: Context) -> RecorderView {
        let view = RecorderView()
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ view: RecorderView, context: Context) {
        view.onModifiers = onModifiers
        view.onCapture = onCapture
        view.onCancel = onCancel
    }

    final class RecorderView: NSView {
        var onModifiers: ((NSEvent.ModifierFlags) -> Void)?
        var onCapture: ((String) -> Void)?
        var onCancel: (() -> Void)?

        override var acceptsFirstResponder: Bool { true }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.window?.makeFirstResponder(self)
            }
        }

        override func mouseDown(with event: NSEvent) {
            window?.makeFirstResponder(self)
        }

        override func keyDown(with event: NSEvent) {
            capture(event)
        }

        // Grab shortcuts like cmd+w before the menu does.
        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            guard window?.firstResponder === self else { return false }
            capture(event)
            return true
        }

        override func flagsChanged(with event: NSEvent) {
            onModifiers?(event.modifierFlags.intersection(.deviceIndependentFlagsMask))
        }

        private func capture(_ event: NSEvent) {
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if event.keyCode == UInt16(kVK_Escape), mods.isDisjoint(with: [.control, .option, .shift, .command]) {
                onCancel?()
                return
            }
            guard let trigger = Shortcut.trigger(
                keyCode: event.keyCode,
                characters: event.characters(byApplyingModifiers: []),
                modifiers: mods) else { return }
            onCapture?(trigger)
        }
    }
}
