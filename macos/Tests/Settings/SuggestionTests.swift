import AppKit
import SwiftUI
import Testing
@testable import Ghostty
@testable import GhosttyKit

@Suite
struct SuggestionTests {
    private func names(_ values: [String]) -> [Suggestion] {
        values.map { Suggestion(value: $0, section: nil, fontName: nil) }
    }

    @Test func prefixMatchesComeFirst() {
        let all = names(["Dalabas", "Alabaster", "Alien Blood"])
        #expect(Suggestion.matches(all, query: "ala").map(\.value) == ["Alabaster", "Dalabas"])
    }

    @Test func emptyQueryHasNoMatches() {
        #expect(Suggestion.matches(names(["Alabaster"]), query: "").isEmpty)
    }

    @Test func limitIsRespected() {
        let all = names((1...20).map { "Theme \($0)" })
        #expect(Suggestion.matches(all, query: "theme", limit: 8).count == 8)
    }

    @Test @MainActor func highlightingDoesNotCommit() {
        var commits = 0
        var text = "Ala"
        let field = SuggestionField(
            text: Binding(get: { text }, set: { text = $0 }), placeholder: "",
            suggestions: names(["Alabaster", "Alien Blood", "Dalabas"]), onCommit: { commits += 1 })
        let coordinator = field.makeCoordinator()
        let box = NSComboBox()
        box.usesDataSource = true
        box.dataSource = coordinator
        box.stringValue = "Ala"
        coordinator.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: box))
        let before = coordinator.numberOfItems(in: box)
        box.selectItem(at: 0)
        coordinator.comboBoxSelectionDidChange(Notification(name: NSComboBox.selectionDidChangeNotification, object: box))
        #expect(commits == 0)
        #expect(coordinator.numberOfItems(in: box) == before)
    }

    /// A theme row that follows the model, as the Settings list shows it.
    private struct Row: View {
        @ObservedObject var model: SettingsModel

        var body: some View {
            if let option = model.options.first(where: { $0.key == "theme" }) {
                SettingsRowView(model: model, option: option)
            }
        }
    }

    private func theme(_ value: String) -> SettingsOption {
        SettingsOption(
            key: "theme", kind: .string, help: "", enumValues: [], values: [value], defaults: [],
            source: .file(path: "/c/config", line: 1), entrySources: [])
    }

    private func comboBox(in view: NSView) -> NSComboBox? {
        if let box = view as? NSComboBox { return box }
        return view.subviews.lazy.compactMap { comboBox(in: $0) }.first
    }

    @Test @MainActor func showsTextChangedElsewhere() async throws {
        let model = SettingsModel(config: try TemporaryConfig(""), defaultTarget: "/c/config")
        model.options = [theme("Atom One Dark")]
        let host = NSHostingView(rootView: Row(model: model))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 200),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(nanoseconds: 100_000_000)
        let box = try #require(comboBox(in: host))
        #expect(box.stringValue == "Atom One Dark")

        model.options = [theme("3024 Day")]
        try await Task.sleep(nanoseconds: 200_000_000)
        host.layoutSubtreeIfNeeded()
        #expect(box.stringValue == "3024 Day")
    }

    @Test func shellsSkipCommentsAndBlankLines() {
        #expect(Shells.parse("# c\n/bin/zsh\n\n/bin/bash\n") == ["/bin/zsh", "/bin/bash"])
    }
}
