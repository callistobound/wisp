import Foundation

/// Watches config files and their parent directories, calling `onChange` on the main
/// queue after a debounce. Directories are watched because atomic saves swap inodes.
final class ConfigFileWatcher {
    struct Signature: Equatable {
        let dev: dev_t
        let ino: ino_t
        let size: off_t
        let mtime: timespec

        init?(path: String) {
            var st = stat()
            guard stat(path, &st) == 0 else { return nil }
            dev = st.st_dev
            ino = st.st_ino
            size = st.st_size
            mtime = st.st_mtimespec
        }

        static func == (a: Self, b: Self) -> Bool {
            a.dev == b.dev && a.ino == b.ino && a.size == b.size &&
                a.mtime.tv_sec == b.mtime.tv_sec && a.mtime.tv_nsec == b.mtime.tv_nsec
        }
    }

    private struct Watch {
        let source: DispatchSourceFileSystemObject
        let dev: dev_t
        let ino: ino_t
    }

    private let queue = DispatchQueue(label: "com.mitchellh.ghostty.config-file-watcher")
    private let debounce: TimeInterval
    private let onChange: () -> Void

    // Only touched on `queue`.
    private var signatures: [String: Signature?] = [:]
    private var watches: [String: Watch] = [:]
    private var dirty = false
    /// Set by `rebaseline`; until the next fire, only signature changes count.
    private var quiet = false
    private var pending: DispatchWorkItem?

    init(paths: [String], debounce: TimeInterval = 0.2, onChange: @escaping () -> Void) {
        self.debounce = debounce
        self.onChange = onChange
        update(paths: paths)
    }

    deinit {
        pending?.cancel()
        watches.values.forEach { $0.source.cancel() }
    }

    /// Stat signatures of each path's resolved target; missing files are omitted.
    static func signatures(paths: [String]) -> [String: Signature] {
        var result: [String: Signature] = [:]
        for target in paths.map(resolve) { result[target] = Signature(path: target) }
        return result
    }

    private static func resolve(_ path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().path
    }

    func update(paths: [String]) {
        let targets = paths.map(Self.resolve)
        queue.sync {
            // Keep existing signatures so a change pending in the debounce isn't lost.
            signatures = Dictionary(targets.map { ($0, signatures[$0] ?? Signature(path: $0)) }) { a, _ in a }
            if targets.isEmpty { pending?.cancel() }
            rearm()
        }
    }

    /// Takes the files as they are now as unchanged, so the events from a write we
    /// already reloaded for don't fire. A later change still differs in signature.
    func rebaseline() {
        queue.sync {
            for path in signatures.keys { signatures[path] = Signature(path: path) }
            dirty = false
            quiet = true
            rearm()
        }
    }

    /// Watches every target and parent directory, reopening any whose inode was replaced.
    private func rearm() {
        let targets = Set(signatures.keys)
        let paths = targets.union(targets.map { ($0 as NSString).deletingLastPathComponent })
        for (path, watch) in watches {
            let current = Signature(path: path)
            if !paths.contains(path) || current?.dev != watch.dev || current?.ino != watch.ino {
                watch.source.cancel()
                watches[path] = nil
            }
        }

        for path in paths where watches[path] == nil {
            guard let current = Signature(path: path) else { continue }
            let fd = open(path, O_EVTONLY)
            guard fd >= 0 else { continue }
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fd, eventMask: [.write, .delete, .rename, .extend], queue: queue)
            let isFile = targets.contains(path)
            source.setEventHandler { [weak self] in self?.handleEvent(file: isFile) }
            source.setCancelHandler { close(fd) }
            source.resume()
            watches[path] = Watch(source: source, dev: current.dev, ino: current.ino)
        }
    }

    private func handleEvent(file: Bool) {
        // Writes to a watched file always count; directory events count only if a target changed.
        if file && !quiet { dirty = true }
        rearm()
        pending?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.fire() }
        pending = item
        queue.asyncAfter(deadline: .now() + debounce, execute: item)
    }

    private func fire() {
        var changed = dirty
        dirty = false
        quiet = false
        for (path, old) in signatures {
            let new = Signature(path: path)
            if new != old { changed = true }
            signatures.updateValue(new, forKey: path)
        }
        guard changed else { return }
        DispatchQueue.main.async { [weak self] in self?.onChange() }
    }
}
