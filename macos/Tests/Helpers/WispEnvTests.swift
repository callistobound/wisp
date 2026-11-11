import Testing
import Foundation
@testable import Ghostty

struct WispEnvTests {
    @Test func prefersWispOverGhostty() {
        let env = ["WISP_X": "w", "GHOSTTY_X": "g"]
        #expect(ProcessInfo.wispEnv("X", in: env) == "w")
    }

    @Test func fallsBackToGhostty() {
        #expect(ProcessInfo.wispEnv("X", in: ["GHOSTTY_X": "g"]) == "g")
    }

    @Test func missingIsNil() {
        #expect(ProcessInfo.wispEnv("X", in: [:]) == nil)
    }
}
