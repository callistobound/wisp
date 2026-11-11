/// Wisp's appcasts, one per channel, published as GitHub release assets.
enum UpdateFeed {
    static func url(for channel: Ghostty.AutoUpdateChannel) -> String {
        switch channel {
        case .stable: "https://github.com/callistobound/wisp/releases/latest/download/appcast.xml"
        case .tip: "https://github.com/callistobound/wisp/releases/download/tip/appcast.xml"
        }
    }
}
