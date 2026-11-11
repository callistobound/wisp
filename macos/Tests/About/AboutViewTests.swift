import Foundation
import Testing
@testable import Ghostty

@Suite
struct AboutViewTests {
    @Test func githubLinkIsWisp() {
        #expect(AboutView.githubURL == URL(string: "https://github.com/callistobound/wisp"))
    }
}
