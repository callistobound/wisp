const std = @import("std");
const Allocator = std.mem.Allocator;
const cli = @import("../cli.zig");

/// Where a config value was set.
pub const Source = union(enum) {
    /// Set by an iterator that has no location.
    other,
    cli: usize,
    file: Line,
    theme: Line,

    pub const Line = struct {
        path: []const u8,
        line: usize,
    };

    pub fn fromLocation(loc: cli.Location, theme_path: ?[]const u8) Source {
        return switch (loc) {
            .none => .other,
            .cli => |n| .{ .cli = n },
            .file => |f| file: {
                const l: Line = .{ .path = f.path, .line = f.line };
                const is_theme = if (theme_path) |tp| std.mem.eql(u8, tp, f.path) else false;
                break :file if (is_theme) .{ .theme = l } else .{ .file = l };
            },
        };
    }

    pub fn clone(self: Source, alloc: Allocator) Allocator.Error!Source {
        return switch (self) {
            .other, .cli => self,
            .file => |v| .{ .file = .{
                .path = try alloc.dupe(u8, v.path),
                .line = v.line,
            } },
            .theme => |v| .{ .theme = .{
                .path = try alloc.dupe(u8, v.path),
                .line = v.line,
            } },
        };
    }
};
