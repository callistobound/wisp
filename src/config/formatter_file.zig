const std = @import("std");
const Allocator = std.mem.Allocator;
const Config = @import("Config.zig");
const Key = @import("key.zig").Key;
const help_strings = @import("help_strings");
const formatter = @import("formatter.zig");

// IMPORTANT: This is in a separate file from formatter.zig because it
// puts a build-time dependency on Config.zig which brings in too much
// into libghostty-vt tests which reference some formattable types.

/// FileFormatter is a formatter implementation that outputs the
/// config in a file-like format. This uses more generous whitespace,
/// can include comments, etc.
pub const FileFormatter = struct {
    alloc: Allocator,
    config: *const Config,

    /// Include comments for documentation of each key
    docs: bool = false,

    /// Only include changed values from the default.
    changed: bool = false,

    /// Include a comment above each entry saying where it was set.
    sources: bool = false,

    /// Implements std.fmt so it can be used directly with std.fmt.
    pub fn format(
        self: FileFormatter,
        writer: *std.Io.Writer,
    ) std.Io.Writer.Error!void {
        @setEvalBranchQuota(10_000);

        // If we're change-tracking then we need the default config to
        // compare against.
        var default: ?Config = if (self.changed)
            Config.default(self.alloc) catch return error.WriteFailed
        else
            null;
        defer if (default) |*v| v.deinit();

        inline for (@typeInfo(Config).@"struct".field_names, @typeInfo(Config).@"struct".field_types) |field, field_type| {
            if (field[0] == '_') continue;

            const value = @field(self.config, field);
            const do_format = if (default) |*d| format: {
                const key = @field(Key, field);
                break :format d.changed(self.config, key);
            } else true;

            if (do_format) {
                const do_docs = self.docs and @hasDecl(help_strings.Config, field);
                if (do_docs) {
                    const help = @field(help_strings.Config, field);
                    var lines = std.mem.splitScalar(u8, help, '\n');
                    while (lines.next()) |line| {
                        try writer.print("# {s}\n", .{line});
                    }
                }

                if (self.sources) {
                    if (self.config.sourceOf(@field(Key, field))) |src| switch (src) {
                        .file => |l| try writer.print("# set in {s}:{d}\n", .{ l.path, l.line }),
                        .theme => |l| try writer.print("# set by theme {s}:{d}\n", .{ l.path, l.line }),
                        .cli => |n| try writer.print("# set by CLI argument {d}\n", .{n}),
                        .other => {},
                    };
                }

                formatter.formatEntry(
                    field_type,
                    field,
                    value,
                    writer,
                ) catch return error.WriteFailed;

                if (do_docs) try writer.print("\n", .{});
            }
        }
    }
};

test "format default config" {
    const testing = std.testing;
    const alloc = testing.allocator;
    var cfg = try Config.default(alloc);
    defer cfg.deinit();

    var buf: std.Io.Writer.Allocating = .init(alloc);
    defer buf.deinit();

    // We just make sure this works without errors. We aren't asserting output.
    const fmt: FileFormatter = .{
        .alloc = alloc,
        .config = &cfg,
    };
    try fmt.format(&buf.writer);

    //std.log.warn("{s}", .{buf.written()});
}

test "format default config changed" {
    const testing = std.testing;
    const alloc = testing.allocator;
    var cfg = try Config.default(alloc);
    defer cfg.deinit();
    cfg.@"font-size" = 42;

    var buf: std.Io.Writer.Allocating = .init(alloc);
    defer buf.deinit();

    // We just make sure this works without errors. We aren't asserting output.
    const fmt: FileFormatter = .{
        .alloc = alloc,
        .config = &cfg,
        .changed = true,
    };
    try fmt.format(&buf.writer);

    //std.log.warn("{s}", .{buf.written()});
}

test "format sources" {
    const testing = std.testing;
    const alloc = testing.allocator;
    var cfg = try Config.default(alloc);
    defer cfg.deinit();
    cfg.@"font-size" = 14;
    try cfg._sources.put(cfg._arena.?.allocator(), "font-size", .{
        .file = .{ .path = "/x/config.ghostty", .line = 3 },
    });

    var buf: std.Io.Writer.Allocating = .init(alloc);
    defer buf.deinit();

    const fmt: FileFormatter = .{
        .alloc = alloc,
        .config = &cfg,
        .changed = true,
        .sources = true,
    };
    try fmt.format(&buf.writer);

    try testing.expect(std.mem.indexOf(
        u8,
        buf.written(),
        "# set in /x/config.ghostty:3\nfont-size = 14\n",
    ) != null);
}

test "format sources theme, cli, and docs" {
    const testing = std.testing;
    const alloc = testing.allocator;
    var cfg = try Config.default(alloc);
    defer cfg.deinit();
    const arena_alloc = cfg._arena.?.allocator();
    cfg.@"font-size" = 14;
    try cfg._sources.put(arena_alloc, "font-size", .{
        .theme = .{ .path = "/x/themes/t", .line = 5 },
    });
    cfg.@"font-thicken" = true;
    try cfg._sources.put(arena_alloc, "font-thicken", .{ .cli = 2 });

    var buf: std.Io.Writer.Allocating = .init(alloc);
    defer buf.deinit();

    const fmt: FileFormatter = .{
        .alloc = alloc,
        .config = &cfg,
        .changed = true,
        .sources = true,
        .docs = true,
    };
    try fmt.format(&buf.writer);
    const out = buf.written();

    try testing.expect(std.mem.indexOf(
        u8,
        out,
        "# set by theme /x/themes/t:5\nfont-size = 14\n",
    ) != null);
    try testing.expect(std.mem.indexOf(
        u8,
        out,
        "# set by CLI argument 2\nfont-thicken = true\n",
    ) != null);

    // Docs come first, then the source line directly above the entry.
    const help = help_strings.Config.@"font-size";
    const last = help[(std.mem.lastIndexOfScalar(u8, help, '\n') orelse 0) + 1 ..];
    const expected = try std.fmt.allocPrint(
        alloc,
        "# {s}\n# set by theme /x/themes/t:5\nfont-size = 14\n",
        .{last},
    );
    defer alloc.free(expected);
    try testing.expect(std.mem.indexOf(u8, out, expected) != null);
}
