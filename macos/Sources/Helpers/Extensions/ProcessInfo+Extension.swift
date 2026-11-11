import Foundation

extension ProcessInfo {
    /// Reads `WISP_<name>`, falling back to `GHOSTTY_<name>`.
    static func wispEnv(
        _ name: String,
        in env: [String: String] = ProcessInfo.processInfo.environment
    ) -> String? {
        env["WISP_" + name] ?? env["GHOSTTY_" + name]
    }
}
