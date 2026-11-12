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

    @Test func featureStateFollowsEntries() {
        #expect(FontCatalog.featureIsOn("calt", entries: []))
        #expect(!FontCatalog.featureIsOn("ss01", entries: []))
        #expect(!FontCatalog.featureIsOn("calt", entries: ["-calt"]))
        #expect(FontCatalog.featureIsOn("calt", entries: ["-calt", "calt"]))
        #expect(!FontCatalog.featureIsOn("liga", entries: ["-calt, -liga"]))
        #expect(!FontCatalog.featureIsOn("calt", entries: ["calt=0"]))
        #expect(FontCatalog.featureIsOn("ss01", entries: ["ss01 on"]))
    }

    @Test func featureEditsTurnDefaultsOff() {
        let off = FontCatalog.featureEdit("calt", on: false, entries: [])
        #expect(off.remove.isEmpty && off.add == "-calt")
        let on = FontCatalog.featureEdit("calt", on: true, entries: ["-calt"])
        #expect(on.remove == ["-calt"] && on.add == nil)
        let ss = FontCatalog.featureEdit("ss01", on: false, entries: ["ss01"])
        #expect(ss.remove == ["ss01"] && ss.add == nil)
        let multi = FontCatalog.featureEdit("liga", on: true, entries: ["-calt, -liga"])
        #expect(multi.remove.isEmpty && multi.add == "liga")
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
