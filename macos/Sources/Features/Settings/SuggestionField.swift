import AppKit
import SwiftUI

/// A value the user might want, optionally drawn in its own font.
struct Suggestion: Hashable {
    let value: String
    let section: String?
    let fontName: String?

    /// Case-insensitive matches for `query`: prefix matches first, then other
    /// substring matches, each group in the original order.
    static func matches(_ all: [Suggestion], query: String, limit: Int = 8) -> [Suggestion] {
        guard !query.isEmpty else { return [] }
        var prefix: [Suggestion] = []
        var other: [Suggestion] = []
        for s in all {
            guard let range = s.value.range(of: query, options: .caseInsensitive) else { continue }
            if range.lowerBound == s.value.startIndex { prefix.append(s) } else { other.append(s) }
        }
        return Array((prefix + other).prefix(limit))
    }
}

/// The login shells in /etc/shells.
enum Shells {
    static func parse(_ etcShells: String) -> [String] {
        etcShells.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
    }

    static var installed: [String] {
        parse((try? String(contentsOfFile: "/etc/shells", encoding: .utf8)) ?? "")
    }
}

/// A text field that completes from `suggestions` as you type; ↓ or the arrow
/// lists every match. Anything can still be typed.
struct SuggestionField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let suggestions: [Suggestion]
    let onCommit: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSComboBox {
        let box = NSComboBox()
        box.usesDataSource = true
        box.completes = true
        box.numberOfVisibleItems = 10
        box.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        box.placeholderString = placeholder
        box.dataSource = context.coordinator
        box.delegate = context.coordinator
        box.target = context.coordinator
        box.action = #selector(Coordinator.commit(_:))
        return box
    }

    func updateNSView(_ box: NSComboBox, context: Context) {
        let changed = context.coordinator.parent.suggestions != suggestions
        context.coordinator.parent = self
        if box.stringValue != text { box.stringValue = text }
        box.placeholderString = placeholder
        if changed { box.reloadData() }
    }

    final class Coordinator: NSObject, NSComboBoxDataSource, NSComboBoxDelegate {
        var parent: SuggestionField
        /// What the user typed; highlighting an item in the list doesn't change it.
        private var query = ""

        init(_ parent: SuggestionField) { self.parent = parent }

        /// Every suggestion when nothing's typed, else the matches.
        private func items(_ box: NSComboBox) -> [Suggestion] {
            query.isEmpty
                ? parent.suggestions
                : Suggestion.matches(parent.suggestions, query: query, limit: 200)
        }

        func numberOfItems(in comboBox: NSComboBox) -> Int { items(comboBox).count }

        func comboBox(_ comboBox: NSComboBox, objectValueForItemAt index: Int) -> Any? {
            let list = items(comboBox)
            guard index < list.count else { return nil }
            let s = list[index]
            guard let name = s.fontName, let font = NSFont(name: name, size: NSFont.systemFontSize) else {
                return s.value
            }
            return NSAttributedString(string: s.value, attributes: [.font: font])
        }

        func comboBox(_ comboBox: NSComboBox, completedString string: String) -> String? {
            parent.suggestions.first { $0.value.lowercased().hasPrefix(string.lowercased()) }?.value
        }

        func comboBox(_ comboBox: NSComboBox, indexOfItemWithStringValue string: String) -> Int {
            items(comboBox).firstIndex { $0.value == string } ?? NSNotFound
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let box = notification.object as? NSComboBox else { return }
            query = box.stringValue
            parent.text = box.stringValue
        }

        /// Highlighting (arrow keys) only fills the field; Enter or a click commits.
        func comboBoxSelectionDidChange(_ notification: Notification) {
            guard let box = notification.object as? NSComboBox, box.indexOfSelectedItem >= 0 else { return }
            let list = items(box)
            guard box.indexOfSelectedItem < list.count else { return }
            parent.text = list[box.indexOfSelectedItem].value
        }

        @objc func commit(_ sender: NSComboBox) {
            parent.text = sender.stringValue
            parent.onCommit()
        }
    }
}
