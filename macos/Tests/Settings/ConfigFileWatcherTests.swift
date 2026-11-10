import Foundation
import Testing
@testable import Ghostty

@Suite
@MainActor
struct ConfigFileWatcherTests {
    /// Only touched on the main queue.
    private final class Counter {
        var count = 0
    }

    private func tempFile(_ text: String = "a = 1\n") throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("config.ghostty")
        try text.write(to: file, atomically: false, encoding: .utf8)
        return file
    }

    /// Writes a temp file beside `file` and renames it over `file`, like an editor's atomic save.
    private func atomicReplace(_ file: URL, with text: String) throws {
        let tmp = file.deletingLastPathComponent().appendingPathComponent(UUID().uuidString)
        try text.write(to: tmp, atomically: false, encoding: .utf8)
        #expect(rename(tmp.path, file.path) == 0)
    }

    private func wait(until condition: () -> Bool, timeout: TimeInterval = 2) async throws -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline { return false }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        return true
    }

    @Test func atomicReplaceTriggersAndUpdateWatchesNewFiles() async throws {
        let first = try tempFile()
        let second = try tempFile()
        defer {
            try? FileManager.default.removeItem(at: first.deletingLastPathComponent())
            try? FileManager.default.removeItem(at: second.deletingLastPathComponent())
        }

        let counter = Counter()
        let watcher = ConfigFileWatcher(paths: [first.path], debounce: 0.05) { counter.count += 1 }

        try atomicReplace(first, with: "a = 2\n")
        #expect(try await wait { counter.count == 1 })

        // A second replace still triggers after the inode swap.
        try atomicReplace(first, with: "a = 3\n")
        #expect(try await wait { counter.count == 2 })

        watcher.update(paths: [first.path, second.path])
        try atomicReplace(second, with: "b = 1\n")
        #expect(try await wait { counter.count == 3 })
    }

    @Test func unrelatedFilesInTheDirectoryDoNotTrigger() async throws {
        let file = try tempFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }

        let counter = Counter()
        let watcher = ConfigFileWatcher(paths: [file.path], debounce: 0.05) { counter.count += 1 }
        try "x".write(to: file.deletingLastPathComponent().appendingPathComponent("other"), atomically: true, encoding: .utf8)
        #expect(try await wait(until: { counter.count > 0 }, timeout: 0.5) == false)
        _ = watcher
    }

    @Test func emptyPathsStopWatching() async throws {
        let file = try tempFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }

        let counter = Counter()
        let watcher = ConfigFileWatcher(paths: [file.path], debounce: 0.05) { counter.count += 1 }
        watcher.update(paths: [])
        try atomicReplace(file, with: "a = 2\n")
        #expect(try await wait(until: { counter.count > 0 }, timeout: 0.5) == false)
    }
}
