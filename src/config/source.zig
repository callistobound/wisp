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
            .file => |f| if (theme_path) |tp|
                if (std.mem.eql(u8, tp, f.path))
                    .{ .theme = .{ .path = f.path, .line = f.line } }
                else
                    .{ .file = .{ .path = f.path, .line = f.line } }
            else
                .{ .file = .{ .path = f.path, .line = f.line } },
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
