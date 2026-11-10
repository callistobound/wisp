const builtin = @import("builtin");
const std = @import("std");
const inputpkg = @import("../input.zig");
const global = @import("../global.zig");
const String = @import("../main_c.zig").String;

const Config = @import("Config.zig");
const c_get = @import("c_get.zig");
const edit = @import("edit.zig");
const file_edit = @import("file_edit.zig");
const schema = @import("schema.zig");
const Source = @import("source.zig").Source;
const Key = @import("key.zig").Key;

const lib = @import("../lib/main.zig");

const log = std.log.scoped(.config);

/// Create a new configuration filled with the initial default values.
export fn ghostty_config_new() ?*Config {
    const result = global.alloc().create(Config) catch |err| {
        log.err("error allocating config err={}", .{err});
        return null;
    };

    result.* = Config.default(global.alloc()) catch |err| {
        log.err("error creating config err={}", .{err});
        global.alloc().destroy(result);
        return null;
    };

    return result;
}

export fn ghostty_config_free(ptr: ?*Config) void {
    if (ptr) |v| {
        v.deinit();
        global.alloc().destroy(v);
    }
}

/// Deep clone the configuration.
export fn ghostty_config_clone(self: *Config) ?*Config {
    const result = global.alloc().create(Config) catch |err| {
        log.err("error allocating config err={}", .{err});
        return null;
    };

    result.* = self.clone(global.alloc()) catch |err| {
        log.err("error cloning config err={}", .{err});
        global.alloc().destroy(result);
        return null;
    };

    return result;
}

/// Load the configuration from the CLI args.
export fn ghostty_config_load_cli_args(self: *Config) void {
    self.loadCliArgs(global.alloc()) catch |err| {
        log.err("error loading config err={}", .{err});
    };
}

/// Load the configuration from the default file locations. This
/// is usually done first. The default file locations are locations
/// such as the home directory.
export fn ghostty_config_load_default_files(self: *Config) void {
    self.loadDefaultFiles(global.alloc()) catch |err| {
        log.err("error loading config err={}", .{err});
    };
}

/// Load the configuration from a specific file path.
/// The path must be null-terminated.
export fn ghostty_config_load_file(self: *Config, path: [*:0]const u8) void {
    const path_slice = std.mem.span(path);
    self.loadFile(global.alloc(), path_slice) catch |err| {
        log.err("error loading config from file path={s} err={}", .{ path_slice, err });
    };
}

/// Load the configuration from the user-specified configuration
/// file locations in the previously loaded configuration. This will
/// recursively continue to load up to a built-in limit.
export fn ghostty_config_load_recursive_files(self: *Config) void {
    self.loadRecursiveFiles(global.alloc()) catch |err| {
        log.err("error loading config err={}", .{err});
    };
}

export fn ghostty_config_finalize(self: *Config) void {
    self.finalize() catch |err| {
        log.err("error finalizing config err={}", .{err});
    };
}

export fn ghostty_config_get(
    self: *Config,
    ptr: *anyopaque,
    key_str: [*]const u8,
    len: usize,
) bool {
    @setEvalBranchQuota(10_000);
    const key = std.meta.stringToEnum(Key, key_str[0..len]) orelse return false;
    return c_get.get(self, key, ptr);
}

export fn ghostty_config_trigger(
    self: *Config,
    str: [*]const u8,
    len: usize,
) inputpkg.Binding.Trigger.C {
    return config_trigger_(self, str[0..len]) catch |err| err: {
        log.err("error finding trigger err={}", .{err});
        break :err .{};
    };
}

fn config_trigger_(
    self: *Config,
    str: []const u8,
) !inputpkg.Binding.Trigger.C {
    const action = try inputpkg.Binding.Action.parse(str);
    const trigger: inputpkg.Binding.Trigger = self.keybind.set.getTrigger(action) orelse .{};
    return trigger.cval();
}

export fn ghostty_config_diagnostics_count(self: *Config) u32 {
    return @intCast(self._diagnostics.items().len);
}

export fn ghostty_config_get_diagnostic(self: *Config, idx: u32) Diagnostic {
    const items = self._diagnostics.items();
    if (idx >= items.len) return .{};
    const message = self._diagnostics.precompute.messages.items[idx];
    return .{ .message = message.ptr };
}

export fn ghostty_config_open_path() String {
    const path = edit.openPath(global.alloc()) catch |err| {
        log.err("error opening config in editor err={}", .{err});
        return .empty;
    };

    return .fromSlice(path);
}

/// Sync with ghostty_diagnostic_s
const Diagnostic = extern struct {
    message: [*:0]const u8 = "",
};

/// Sync with ghostty_config_source_e
const SourceKind = enum(c_int) { default, file, theme, cli, other };

/// Sync with ghostty_config_source_s
const CSource = extern struct {
    kind: SourceKind = .default,
    path: [*:0]const u8 = "",
    line: usize = 0,
};

/// Sync with ghostty_config_option_s
const COption = extern struct {
    key: [*:0]const u8 = "",
    kind: schema.Kind = .other,
    help: [*:0]const u8 = "",
    enum_values: [*]const [*:0]const u8 = &.{},
    enum_values_len: usize = 0,
    values: [*]const [*:0]const u8 = &.{},
    values_len: usize = 0,
    defaults: [*]const [*:0]const u8 = &.{},
    defaults_len: usize = 0,
    source: CSource = .{},
    entry_sources: [*]const CSource = &.{},
    entry_sources_len: usize = 0,
};

/// Sync with ghostty_config_edit_op_e
const EditOp = enum(c_int) { set, unset, add, remove };

/// Sync with ghostty_config_edit_result_e
const EditResult = enum(c_int) {
    ok,
    unknown_key,
    invalid_value,
    repeatable_key,
    dangling_symlink,
    hard_link,
    access_denied,
    @"error",
};

/// The schema plus its C-shaped options, all in the schema's arena.
const SchemaHandle = struct {
    schema: schema.Schema,
    options: []const COption,
};

export fn ghostty_config_schema_new(config: *const Config) ?*SchemaHandle {
    return schemaNew(config) catch |err| {
        log.err("error building config schema err={}", .{err});
        return null;
    };
}

fn schemaNew(config: *const Config) !*SchemaHandle {
    const alloc = global.alloc();
    const handle = try alloc.create(SchemaHandle);
    errdefer alloc.destroy(handle);
    handle.schema = try .init(alloc, config);
    errdefer handle.schema.deinit();

    const a = handle.schema.arena.allocator();
    const options = try a.alloc(COption, handle.schema.options.len);
    for (handle.schema.options, options) |opt, *dst| {
        const sources = try a.alloc(CSource, opt.entry_sources.len);
        for (opt.entry_sources, sources) |src, *s| s.* = try cSource(a, src);
        dst.* = .{
            .key = opt.key.ptr,
            .kind = opt.kind,
            .help = opt.help.ptr,
            .enum_values = (try cStrings(a, opt.enum_values)).ptr,
            .enum_values_len = opt.enum_values.len,
            .values = (try cStrings(a, opt.values)).ptr,
            .values_len = opt.values.len,
            .defaults = (try cStrings(a, opt.defaults)).ptr,
            .defaults_len = opt.defaults.len,
            .source = try cSource(a, opt.source),
            .entry_sources = sources.ptr,
            .entry_sources_len = sources.len,
        };
    }
    handle.options = options;
    return handle;
}

fn cStrings(a: std.mem.Allocator, strs: []const [:0]const u8) ![]const [*:0]const u8 {
    const out = try a.alloc([*:0]const u8, strs.len);
    for (strs, out) |s, *d| d.* = s.ptr;
    return out;
}

fn cSource(a: std.mem.Allocator, src: ?Source) !CSource {
    const s = src orelse return .{};
    return switch (s) {
        .other => .{ .kind = .other },
        .cli => |n| .{ .kind = .cli, .line = n },
        .file => |l| .{ .kind = .file, .path = try a.dupeSentinel(u8, l.path, 0), .line = l.line },
        .theme => |l| .{ .kind = .theme, .path = try a.dupeSentinel(u8, l.path, 0), .line = l.line },
    };
}

export fn ghostty_config_schema_free(ptr: ?*SchemaHandle) void {
    if (ptr) |v| {
        v.schema.deinit();
        global.alloc().destroy(v);
    }
}

export fn ghostty_config_schema_options_len(self: *const SchemaHandle) usize {
    return self.options.len;
}

export fn ghostty_config_schema_option(self: *const SchemaHandle, idx: usize) COption {
    if (idx >= self.options.len) return .{};
    return self.options[idx];
}

export fn ghostty_config_schema_files_len(self: *const SchemaHandle) usize {
    return self.schema.files.len;
}

export fn ghostty_config_schema_file(self: *const SchemaHandle, idx: usize) [*:0]const u8 {
    if (idx >= self.schema.files.len) return "";
    return self.schema.files[idx].ptr;
}

/// Edit the config file at absolute `path`. `value` is ignored for unset.
export fn ghostty_config_edit(
    path: [*:0]const u8,
    op_raw: c_int,
    key_ptr: [*]const u8,
    key_len: usize,
    value_ptr: ?[*]const u8,
    value_len: usize,
) EditResult {
    const path_slice = std.mem.span(path);
    const key = key_ptr[0..key_len];
    const value: []const u8 = if (value_ptr) |v| v[0..value_len] else "";
    const op: file_edit.Op = switch (std.enums.fromInt(EditOp, op_raw) orelse {
        log.warn("config edit has an invalid op={}", .{op_raw});
        return .@"error";
    }) {
        .set => .{ .set = .{ .key = key, .value = value } },
        .unset => .{ .unset = key },
        .add => .{ .add = .{ .key = key, .value = value } },
        .remove => .{ .remove = .{ .key = key, .value = value } },
    };
    if (!std.fs.path.isAbsolute(path_slice)) {
        log.warn("config edit path is not absolute path={s}", .{path_slice});
        return .@"error";
    }

    const alloc = global.alloc();
    file_edit.validate(alloc, op) catch |err| return editResult(err, path_slice);
    file_edit.applyToFile(global.io(), alloc, path_slice, op) catch |err|
        return editResult(err, path_slice);
    return .ok;
}

fn editResult(err: anyerror, path: []const u8) EditResult {
    return switch (err) {
        error.UnknownKey => .unknown_key,
        error.InvalidValue => .invalid_value,
        error.RepeatableKey => .repeatable_key,
        error.DanglingSymlink => .dangling_symlink,
        error.HardLink => .hard_link,
        error.AccessDenied, error.PermissionDenied => .access_denied,
        else => {
            log.warn("error editing config path={s} err={}", .{ path, err });
            return .@"error";
        },
    };
}

test "ghostty_config_get: bool" {
    const testing = std.testing;
    const alloc = testing.allocator;

    var cfg = try Config.default(alloc);
    defer cfg.deinit();
    cfg.maximize = true;

    var out = false;
    const key = "maximize";
    try testing.expect(ghostty_config_get(&cfg, &out, key, key.len));
    try testing.expect(out);
}

test "ghostty_config_get: enum" {
    const testing = std.testing;
    const alloc = testing.allocator;

    var cfg = try Config.default(alloc);
    defer cfg.deinit();
    cfg.@"window-theme" = .dark;

    var out: [*:0]const u8 = undefined;
    const key = "window-theme";
    try testing.expect(ghostty_config_get(&cfg, @ptrCast(&out), key, key.len));
    const str = std.mem.sliceTo(out, 0);
    try testing.expectEqualStrings("dark", str);
}

test "ghostty_config_get: optional null returns false" {
    const testing = std.testing;
    const alloc = testing.allocator;

    var cfg = try Config.default(alloc);
    defer cfg.deinit();
    cfg.@"unfocused-split-fill" = null;

    var out: Config.Color.C = undefined;
    const key = "unfocused-split-fill";
    try testing.expect(!ghostty_config_get(&cfg, @ptrCast(&out), key, key.len));
}

test "ghostty_config_get: unknown key returns false" {
    const testing = std.testing;
    const alloc = testing.allocator;

    var cfg = try Config.default(alloc);
    defer cfg.deinit();

    var out = false;
    const key = "not-a-real-key";
    try testing.expect(!ghostty_config_get(&cfg, &out, key, key.len));
}

test "ghostty_config_get: optional string null returns true" {
    const testing = std.testing;
    const alloc = testing.allocator;

    var cfg = try Config.default(alloc);
    defer cfg.deinit();
    cfg.title = null;

    var out: ?[*:0]const u8 = undefined;
    const key = "title";
    try testing.expect(ghostty_config_get(&cfg, @ptrCast(&out), key, key.len));
    try testing.expect(out == null);
}

test "ghostty_config_get: float" {
    const testing = std.testing;
    const alloc = testing.allocator;

    var cfg = try Config.default(alloc);
    defer cfg.deinit();
    cfg.@"background-opacity" = 0.42;

    var out: f64 = 0;
    const key = "background-opacity";
    try testing.expect(ghostty_config_get(&cfg, &out, key, key.len));
    try testing.expectApproxEqAbs(@as(f64, 0.42), out, 0.000001);
}

test "ghostty_config_get: struct cval conversion" {
    const testing = std.testing;
    const alloc = testing.allocator;

    var cfg = try Config.default(alloc);
    defer cfg.deinit();
    cfg.background = .{ .r = 12, .g = 34, .b = 56 };

    var out: Config.Color.C = undefined;
    const key = "background";
    try testing.expect(ghostty_config_get(&cfg, @ptrCast(&out), key, key.len));
    try testing.expectEqual(@as(u8, 12), out.r);
    try testing.expectEqual(@as(u8, 34), out.g);
    try testing.expectEqual(@as(u8, 56), out.b);
}

test "ghostty_config_trigger: default keybind" {
    const testing = std.testing;

    var cfg = try Config.default(testing.allocator);
    defer cfg.deinit();

    // Default commands should be fetchable through config_trigger_
    {
        const trigger = try config_trigger_(&cfg, "open_config");
        try testing.expectEqual(.unicode, trigger.tag);
        try testing.expectEqual(@as(u32, ','), trigger.key.unicode);
    }
    {
        const trigger = try config_trigger_(&cfg, "reload_config");
        try testing.expectEqual(.unicode, trigger.tag);
        try testing.expectEqual(@as(u32, ','), trigger.key.unicode);
    }
    // Performable bindings are not tracked in the reverse map,
    // so config_trigger_ should return a default (empty) trigger.
    if (comptime builtin.target.os.tag.isDarwin()) {
        const next = try config_trigger_(&cfg, "navigate_search:next");
        try testing.expectEqual(.physical, next.tag);
        try testing.expectEqual(.unidentified, next.key.physical);

        const prev = try config_trigger_(&cfg, "navigate_search:previous");
        try testing.expectEqual(.physical, prev.tag);
        try testing.expectEqual(.unidentified, prev.key.physical);
    }
    {
        const trigger = try config_trigger_(&cfg, "adjust_selection:left");
        try testing.expectEqual(.physical, trigger.tag);
        try testing.expectEqual(.unidentified, trigger.key.physical);
    }
}

test "CApi: schema" {
    const testing = std.testing;
    const alloc = testing.allocator;
    const internal_os = @import("../os/main.zig");

    var td = try internal_os.TempDir.init();
    defer td.deinit();
    try td.dir.writeFile(testing.io, .{ .sub_path = "config.ghostty", .data = "font-size = 15\n" });
    var buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const path = buf[0..try td.dir.realPathFile(testing.io, "config.ghostty", &buf)];

    var cfg = try Config.default(alloc);
    defer cfg.deinit();
    try cfg.loadFile(alloc, path);
    try cfg.finalize();

    const s = ghostty_config_schema_new(&cfg) orelse return error.TestUnexpectedResult;
    defer ghostty_config_schema_free(s);

    var found = false;
    for (0..ghostty_config_schema_options_len(s)) |i| {
        const opt = ghostty_config_schema_option(s, i);
        if (!std.mem.eql(u8, std.mem.span(opt.key), "font-size")) continue;
        found = true;
        try testing.expectEqual(schema.Kind.float, opt.kind);
        try testing.expectEqual(@as(usize, 1), opt.values_len);
        try testing.expectEqualStrings("15", std.mem.span(opt.values[0]));
        try testing.expectEqual(SourceKind.file, opt.source.kind);
        try testing.expectEqual(@as(usize, 1), opt.source.line);
        try testing.expectEqualStrings(path, std.mem.span(opt.source.path));
    }
    try testing.expect(found);
    try testing.expectEqual(@as(usize, 1), ghostty_config_schema_files_len(s));
    try testing.expectEqualStrings(path, std.mem.span(ghostty_config_schema_file(s, 0)));
}

test "CApi: edit" {
    const testing = std.testing;
    const internal_os = @import("../os/main.zig");

    var td = try internal_os.TempDir.init();
    defer td.deinit();
    try td.dir.writeFile(testing.io, .{ .sub_path = "config.ghostty", .data = "font-size = 12\n" });
    var buf: [std.Io.Dir.max_path_bytes:0]u8 = undefined;
    const len = try td.dir.realPathFile(testing.io, "config.ghostty", &buf);
    buf[len] = 0;
    const path: [*:0]const u8 = buf[0..len :0];

    const Case = struct { key: []const u8, value: []const u8, want: EditResult };
    const cases = [_]Case{
        .{ .key = "font-size", .value = "14", .want = .ok },
        .{ .key = "font-size", .value = "abc", .want = .invalid_value },
        .{ .key = "nope", .value = "1", .want = .unknown_key },
        .{ .key = "keybind", .value = "x", .want = .repeatable_key },
    };
    for (cases) |c| {
        const op: c_int = @backingInt(EditOp.set);
        try testing.expectEqual(c.want, ghostty_config_edit(path, op, c.key.ptr, c.key.len, c.value.ptr, c.value.len));
        var rbuf: [64]u8 = undefined;
        const got = try td.dir.readFile(testing.io, "config.ghostty", &rbuf);
        try testing.expectEqualStrings("font-size = 14\n", got);
    }

    const rel = "config.ghostty";
    try testing.expectEqual(EditResult.@"error", ghostty_config_edit(rel, @backingInt(EditOp.unset), "font-size", 9, null, 0));
}

test "CApi: ghostty.h enums" {
    try lib.checkGhosttyHEnum(schema.Kind, "GHOSTTY_CONFIG_KIND_");
    try lib.checkGhosttyHEnum(SourceKind, "GHOSTTY_CONFIG_SOURCE_");
    try lib.checkGhosttyHEnum(EditOp, "GHOSTTY_CONFIG_EDIT_");
    try lib.checkGhosttyHEnum(EditResult, "GHOSTTY_CONFIG_EDIT_");
}
