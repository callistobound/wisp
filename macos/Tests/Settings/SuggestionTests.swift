import AppKit
import SwiftUI
import Testing
@testable import Ghostty

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

    @Test func shellsSkipCommentsAndBlankLines() {
        #expect(Shells.parse("# c\n/bin/zsh\n\n/bin/bash\n") == ["/bin/zsh", "/bin/bash"])
    }
}
