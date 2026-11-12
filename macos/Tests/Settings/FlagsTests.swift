import Testing
@testable import Ghostty

@Suite
struct FlagsTests {
    private let names = ["cursor", "sudo", "title"]

    @Test func parsesOnAndOff() {
        #expect(FlagSet(names: names, text: "cursor,no-sudo,title").on == ["cursor", "title"])
    }

    @Test func togglingWritesEveryFlag() {
        var flags = FlagSet(names: names, text: "cursor,no-sudo,title")
        flags.on.insert("sudo")
        #expect(flags.text(names: names) == "cursor,sudo,title")
    }

    @Test func falseTurnsEverythingOff() {
        #expect(FlagSet(names: names, text: "false").text(names: names) == "no-cursor,no-sudo,no-title")
        #expect(FlagSet(names: names, text: "true").on == Set(names))
    }

    @Test func unknownNamesAreIgnored() {
        #expect(FlagSet(names: names, text: "cursor,bogus,no-other").on == ["cursor"])
    }
}
