//! Describes every config option for settings UIs.
const std = @import("std");
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const Config = @import("Config.zig");
const Key = @import("key.zig").Key;
const Source = @import("source.zig").Source;
const file_edit = @import("file_edit.zig");
const formatter = @import("formatter.zig");
const global = @import("../global.zig");
const help_strings = @import("help_strings");

pub const Kind = enum(c_int) { bool, @"enum", int, float, color, string, path, repeatable, keybind, other };

/// True if each line for `key` adds an entry rather than replacing the value.
pub fn isRepeatable(key: Key) bool {
    @setEvalBranchQuota(10_000);
    const types = [_]type{
        Config.RepeatableString,
        Config.RepeatablePath,
        @import("RepeatableStringMap.zig"),
        Config.RepeatableFontVariation,
        Config.RepeatableCodepointMap,
        Config.RepeatableClipboardCodepointMap,
        Config.RepeatableLink,
        Config.RepeatableCommand,
        @import("io.zig").RepeatableReadableIO,
        Config.Keybinds,
        Config.Palette,
        @import("../input/key_mods.zig").RemapSet,
    };
    switch (key) {
        inline else => |k| {
            inline for (types) |T| if (@FieldType(Config, @tagName(k)) == T) return true;
            return false;
        },
    }
}

fn Unwrapped(comptime T: type) type {
    return switch (@typeInfo(T)) {
        .optional => |o| o.child,
        else => T,
    };
}

pub fn kindOf(key: Key) Kind {
    @setEvalBranchQuota(10_000);
    switch (key) {
        inline else => |k| {
            const T = Unwrapped(@FieldType(Config, @tagName(k)));
            if (T == Config.Keybinds) return .keybind;
            if (isRepeatable(k)) return .repeatable;
            if (T == bool) return .bool;
            switch (@typeInfo(T)) {
                .@"enum" => return .@"enum",
                .int => return .int,
                .float => return .float,
                else => {},
            }
            if (T == Config.Color) return .color;
            if (T == []const u8 or T == [:0]const u8) return .string;
            if (T == Config.Path) return .path;
            return .other;
        },
    }
}

/// Field names for enum kinds (optional unwrapped), bindable actions for
/// keybind, else empty.
pub fn enumValues(key: Key) []const [:0]const u8 {
    @setEvalBranchQuota(10_000);
    switch (key) {
        inline else => |k| {
            const T = Unwrapped(@FieldType(Config, @tagName(k)));
            if (T == Config.Keybinds) return keybind_actions;
            if (@typeInfo(T) != .@"enum") return &.{};
            const names = comptime names: {
                const fields = @typeInfo(T).@"enum".field_names;
                var out: [fields.len][:0]const u8 = undefined;
                for (fields, 0..) |f, i| out[i] = f;
                const final = out;
                break :names &final;
            };
            return names;
        },
    }
}

/// Actions with no parameter, and one per value for enum parameters.
/// Free-form parameters can't be listed; unbind isn't an action to assign.
const keybind_actions: []const [:0]const u8 = names: {
    @setEvalBranchQuota(100_000);
    const Action = @import("../input/Binding.zig").Action;
    const info = @typeInfo(Action).@"union";
    var out: []const [:0]const u8 = &.{};
    for (info.field_names, info.field_types) |name, T| {
        if (name[0] == '_' or std.mem.eql(u8, name, "unbind")) continue;
        if (T == void) {
            out = out ++ .{name};
        } else if (@typeInfo(T) == .@"enum") {
            for (@typeInfo(T).@"enum".field_names) |v| out = out ++ .{name ++ ":" ++ v};
        }
    }
    const final = out[0..out.len].*;
    break :names &final;
};

pub const Option = struct {
    key: [:0]const u8,
    kind: Kind,
    /// help_strings.Config field, "" if none.
    help: [:0]const u8,
    enum_values: []const [:0]const u8,
    /// Current entries, each the text after "key = ".
    values: []const [:0]const u8,
    /// Same, from Config.default.
    defaults: []const [:0]const u8,
    source: ?Source,
    /// Parallel to `values` for repeatable and keybind kinds, else empty.
    /// Null means default. Matches the formatted text, so a line written
    /// as `a = b` rather than `a=b` is not found.
    entry_sources: []const ?Source,
};

pub const Schema = struct {
    arena: ArenaAllocator,
    /// Every Key, in Key order.
    options: []const Option,
    files: []const [:0]const u8,

    pub fn init(alloc: Allocator, config: *const Config) !Schema {
        var arena = ArenaAllocator.init(alloc);
        errdefer arena.deinit();
        const a = arena.allocator();

        var def = try Config.default(alloc);
        defer def.deinit();

        const keys = std.enums.values(Key);
        const options = try a.alloc(Option, keys.len);
        const loaded = config.loadedFiles();
        for (keys, options) |key, *opt| {
            const kind = kindOf(key);
            const values = try entries(a, config, key);
            opt.* = .{
                .key = try a.dupeSentinel(u8, @tagName(key), 0),
                .kind = kind,
                .help = try helpOf(a, key),
                .enum_values = enumValues(key),
                .values = values,
                .defaults = try entries(a, &def, key),
                .source = if (config.sourceOf(key)) |s| try s.clone(a) else null,
                .entry_sources = if (kind == .repeatable or kind == .keybind)
                    try entrySources(a, loaded, @tagName(key), values)
                else
                    &.{},
            };
        }

        const files = try a.alloc([:0]const u8, loaded.len);
        for (loaded, files) |src, *dst| dst.* = try a.dupeSentinel(u8, src, 0);

        return .{ .arena = arena, .options = options, .files = files };
    }

    pub fn deinit(self: *Schema) void {
        self.arena.deinit();
    }
};

/// Find the last loaded file with each entry, reading files from disk.
fn entrySources(
    a: Allocator,
    loaded: []const []const u8,
    key: []const u8,
    values: []const [:0]const u8,
) Allocator.Error![]const ?Source {
    const out = try a.alloc(?Source, values.len);
    @memset(out, null);
    if (values.len == 0) return out;

    // Walk files last to first, filling each entry from the latest hit.
    var i = loaded.len;
    while (i > 0) {
        i -= 1;
        const path = loaded[i];
        const src = std.Io.Dir.cwd().readFileAlloc(global.io(), path, a, .unlimited) catch continue;
        for (values, out) |v, *dst| {
            if (dst.* != null) continue;
            const line = file_edit.findEntry(src, key, v) orelse continue;
            dst.* = .{ .file = .{ .path = try a.dupe(u8, path), .line = line } };
        }
    }
    return out;
}

fn helpOf(a: Allocator, key: Key) Allocator.Error![:0]const u8 {
    @setEvalBranchQuota(10_000);
    switch (key) {
        inline else => |k| {
            if (!@hasDecl(help_strings.Config, @tagName(k))) return "";
            return try a.dupeSentinel(u8, @field(help_strings.Config, @tagName(k)), 0);
        },
    }
}

/// Format one field and return the text after "key = " for each line.
fn entries(a: Allocator, config: *const Config, key: Key) ![]const [:0]const u8 {
    @setEvalBranchQuota(10_000);
    var aw: std.Io.Writer.Allocating = .init(a);
    defer aw.deinit();

    switch (key) {
        inline else => |k| {
            const name = @tagName(k);
            formatter.formatEntry(
                @FieldType(Config, name),
                name,
                @field(config, name),
                &aw.writer,
            ) catch return error.OutOfMemory;
        },
    }

    const prefix_len = @tagName(key).len + " = ".len;
    var list: std.ArrayList([:0]const u8) = .empty;
    var lines = std.mem.splitScalar(u8, aw.written(), '\n');
    while (lines.next()) |line| {
        if (line.len == 0) continue;
        const text = if (line.len >= prefix_len) line[prefix_len..] else "";
        try list.append(a, try a.dupeSentinel(u8, text, 0));
    }
    return list.toOwnedSlice(a);
}

fn find(schema: *const Schema, key: Key) *const Option {
    return &schema.options[@backingInt(key)];
}

test "schema: kinds" {
    try std.testing.expectEqual(Kind.float, kindOf(.@"font-size"));
    try std.testing.expectEqual(Kind.repeatable, kindOf(.@"font-family"));
    try std.testing.expectEqual(Kind.keybind, kindOf(.keybind));
    try std.testing.expectEqual(Kind.color, kindOf(.background));
    try std.testing.expectEqual(Kind.@"enum", kindOf(.@"cursor-style"));
    try std.testing.expectEqual(Kind.bool, kindOf(.@"window-inherit-font-size"));
    try std.testing.expectEqual(Kind.string, kindOf(.term));

    var found = false;
    for (enumValues(.@"cursor-style")) |v| {
        if (std.mem.eql(u8, v, "block")) found = true;
    }
    try std.testing.expect(found);
    try std.testing.expectEqual(@as(usize, 0), enumValues(.@"font-size").len);
}

test "schema: values, defaults and source" {
    const testing = std.testing;
    const alloc = testing.allocator;
    const internal_os = @import("../os/main.zig");

    var td = try internal_os.TempDir.init();
    defer td.deinit();
    try td.dir.writeFile(testing.io, .{
        .sub_path = "config.ghostty",
        .data = "font-size = 15\nfont-family = A\nfont-family = B\n",
    });
    var buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const path = buf[0..try td.dir.realPathFile(testing.io, "config.ghostty", &buf)];

    var cfg = try Config.default(alloc);
    defer cfg.deinit();
    try cfg.loadFile(alloc, path);
    try cfg.finalize();

    var schema = try Schema.init(alloc, &cfg);
    defer schema.deinit();

    const fs = find(&schema, .@"font-size");
    try testing.expectEqual(@as(usize, 1), fs.values.len);
    try testing.expectEqualStrings("15", fs.values[0]);
    try testing.expectEqual(@as(usize, 1), fs.defaults.len);
    try testing.expectEqual(@as(usize, 1), fs.source.?.file.line);
    try testing.expectEqualStrings(path, fs.source.?.file.path);

    const ff = find(&schema, .@"font-family");
    try testing.expectEqual(@as(usize, 2), ff.values.len);
    try testing.expectEqualStrings("A", ff.values[0]);
    try testing.expectEqualStrings("B", ff.values[1]);

    try testing.expectEqual(@as(usize, 1), schema.files.len);
    try testing.expectEqualStrings(path, schema.files[0]);
    try testing.expect(find(&schema, .@"font-size").help.len > 0);
}

test "schema: keybind entry sources" {
    const testing = std.testing;
    const alloc = testing.allocator;
    const internal_os = @import("../os/main.zig");

    var td = try internal_os.TempDir.init();
    defer td.deinit();
    try td.dir.writeFile(testing.io, .{
        .sub_path = "config.ghostty",
        .data = "keybind = ctrl+a=new_tab\n",
    });
    var buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const path = buf[0..try td.dir.realPathFile(testing.io, "config.ghostty", &buf)];

    var cfg = try Config.default(alloc);
    defer cfg.deinit();
    try cfg.loadFile(alloc, path);
    try cfg.finalize();

    var schema = try Schema.init(alloc, &cfg);
    defer schema.deinit();

    const kb = find(&schema, .keybind);
    try testing.expectEqual(kb.values.len, kb.entry_sources.len);
    var user = false;
    var dflt = false;
    for (kb.values, kb.entry_sources) |v, s| {
        if (std.mem.eql(u8, v, "ctrl+a=new_tab")) {
            try testing.expectEqual(@as(usize, 1), s.?.file.line);
            user = true;
        } else if (s == null) dflt = true;
    }
    try testing.expect(user and dflt);
    try testing.expectEqual(@as(usize, 0), find(&schema, .@"font-size").entry_sources.len);
}

test "schema: keybind actions" {
    const testing = std.testing;
    const Action = @import("../input/Binding.zig").Action;
    const actions = enumValues(.keybind);
    var quick = false;
    var split = false;
    for (actions) |name| {
        try testing.expect(name[0] != '_');
        try testing.expect(!std.mem.eql(u8, name, "unbind"));
        // Each name round-trips, so it matches how bound actions format.
        var aw: std.Io.Writer.Allocating = .init(testing.allocator);
        defer aw.deinit();
        try (try Action.parse(name)).format(&aw.writer);
        try testing.expectEqualStrings(name, aw.written());
        if (std.mem.eql(u8, name, "toggle_quick_terminal")) quick = true;
        if (std.mem.eql(u8, name, "goto_split:left")) split = true;
    }
    try testing.expect(quick and split);
}
