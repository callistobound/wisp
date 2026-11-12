import Testing
@testable import Ghostty

@Suite
@MainActor
struct FontCatalogTests {
    @Test func monospacedFamiliesComeFirst() throws {
        let families = FontCatalog.families()
        let menlo = try #require(families.firstIndex { $0.value == "Menlo" })
        let helvetica = try #require(families.firstIndex { $0.value == "Helvetica" })
        #expect(families[menlo].section == "Monospaced")
        #expect(menlo < helvetica)
        #expect(families[helvetica].section == "Other fonts")
    }

    @Test func stylesOfAFamily() {
        #expect(FontCatalog.styles(family: "Helvetica Neue").contains("Bold"))
    }

    @Test func unknownFamilyHasNothing() {
        #expect(FontCatalog.styles(family: "No Such Font 123").isEmpty)
        #expect(FontCatalog.features(family: "No Such Font 123").isEmpty)
        #expect(FontCatalog.axes(family: "No Such Font 123").isEmpty)
    }

    @Test func primaryFamilyFallsBackToRegular() {
        let values = ["font-family": ["Menlo", "Monaco"], "font-family-bold": []]
        #expect(FontCatalog.primaryFamily(option: "font-style-bold", values: values) == "Menlo")
        #expect(FontCatalog.primaryFamily(option: "font-style", values: ["font-family": []]) == nil)
        #expect(FontCatalog.primaryFamily(option: "font-feature", values: values) == "Menlo")
        let bold = ["font-family": ["Menlo"], "font-family-bold": ["Monaco"]]
        #expect(FontCatalog.primaryFamily(option: "font-variation-bold", values: bold) == "Monaco")
    }
}
