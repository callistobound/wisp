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

    @Test func shellsSkipCommentsAndBlankLines() {
        #expect(Shells.parse("# c\n/bin/zsh\n\n/bin/bash\n") == ["/bin/zsh", "/bin/bash"])
    }
}
