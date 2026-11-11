import Testing
@testable import Ghostty

@Suite
struct UpdateFeedTests {
    @Test func feedPerChannel() {
        #expect(UpdateFeed.url(for: .stable) == "https://github.com/callistobound/wisp/releases/latest/download/appcast.xml")
        #expect(UpdateFeed.url(for: .tip) == "https://github.com/callistobound/wisp/releases/download/tip/appcast.xml")
    }
}
