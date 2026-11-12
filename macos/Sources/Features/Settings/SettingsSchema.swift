import Foundation
import GhosttyKit

/// Where an option's effective value came from.
enum SettingsSource: Equatable {
    case `default`
    case file(path: String, line: Int)
    case theme(path: String)
    case cli
    case other

    init(_ c: ghostty_config_source_s) {
        switch c.kind {
        case GHOSTTY_CONFIG_SOURCE_DEFAULT: self = .default
        case GHOSTTY_CONFIG_SOURCE_FILE: self = .file(path: String(cString: c.path), line: Int(c.line))
        case GHOSTTY_CONFIG_SOURCE_THEME: self = .theme(path: String(cString: c.path))
        case GHOSTTY_CONFIG_SOURCE_CLI: self = .cli
        default: self = .other
        }
    }
}

/// One config option, copied out of the C schema.
struct SettingsOption: Identifiable {
    enum Kind {
        case bool, `enum`, int, float, color, string, path, repeatable, keybind, other, flags

        init(_ c: ghostty_config_kind_e) {
            switch c {
            case GHOSTTY_CONFIG_KIND_BOOL: self = .bool
            case GHOSTTY_CONFIG_KIND_ENUM: self = .enum
            case GHOSTTY_CONFIG_KIND_INT: self = .int
            case GHOSTTY_CONFIG_KIND_FLOAT: self = .float
            case GHOSTTY_CONFIG_KIND_COLOR: self = .color
            case GHOSTTY_CONFIG_KIND_STRING: self = .string
            case GHOSTTY_CONFIG_KIND_PATH: self = .path
            case GHOSTTY_CONFIG_KIND_REPEATABLE: self = .repeatable
            case GHOSTTY_CONFIG_KIND_KEYBIND: self = .keybind
            case GHOSTTY_CONFIG_KIND_FLAGS: self = .flags
            default: self = .other
            }
        }
    }

    let key: String
    let kind: Kind
    let help: String
    let enumValues: [String]
    /// Empty when unset.
    let values: [String]
    /// Empty when the default is unset.
    let defaults: [String]
    let source: SettingsSource
    let entrySources: [SettingsSource]
    var id: String { key }

    /// The source of entry `i`. One found in no file that isn't a default was
    /// written in a form the formatter doesn't reproduce, so it's `.other`.
    func entrySource(_ i: Int) -> SettingsSource {
        let source = i < entrySources.count ? entrySources[i] : .default
        guard source == .default, values.indices.contains(i), !defaults.contains(values[i]) else { return source }
        return .other
    }
}

/// Owns a `ghostty_config_schema_t` and exposes it as Swift values.
final class SettingsSchema {
    let options: [SettingsOption]
    let files: [String]

    private let schema: ghostty_config_schema_t?

    init(config: Ghostty.Config) {
        schema = config.config.flatMap { ghostty_config_schema_new($0) }
        guard let schema else {
            options = []
            files = []
            return
        }

        options = (0..<ghostty_config_schema_options_len(schema)).map { i in
            let o = ghostty_config_schema_option(schema, i)
            return SettingsOption(
                key: String(cString: o.key),
                kind: .init(o.kind),
                help: String(cString: o.help),
                enumValues: Self.strings(o.enum_values, o.enum_values_len),
                values: Self.unset(Self.strings(o.values, o.values_len)),
                defaults: Self.unset(Self.strings(o.defaults, o.defaults_len)),
                source: .init(o.source),
                entrySources: (0..<Int(o.entry_sources_len)).map { .init(o.entry_sources[$0]) })
        }
        files = (0..<ghostty_config_schema_files_len(schema)).map {
            String(cString: ghostty_config_schema_file(schema, $0))
        }
    }

    deinit {
        ghostty_config_schema_free(schema)
    }

    private static func strings(_ ptr: UnsafePointer<UnsafePointer<CChar>?>?, _ len: UInt) -> [String] {
        guard let ptr else { return [] }
        return (0..<Int(len)).map { ptr[$0].map { String(cString: $0) } ?? "" }
    }

    // A null optional or an empty repeatable comes through as [""].
    private static func unset(_ values: [String]) -> [String] {
        values == [""] ? [] : values
    }
}
