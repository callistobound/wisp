const std = @import("std");
const builtin = @import("builtin");
const assert = @import("../quirks.zig").inlineAssert;
const Allocator = std.mem.Allocator;
const internal_os = @import("../os/main.zig");
const global = @import("../global.zig");

const log = std.log.scoped(.config);

/// The XDG config subdirectory: "wisp", or "ghostty" if only that
/// exists. This only stats; it never creates anything. The returned
/// value is static and must not be freed.
pub fn configDirName(alloc: Allocator) ![]const u8 {
    var environ_map = try global.environMap();
    defer environ_map.deinit();
    return try configDirNameIn(global.io(), alloc, &environ_map);
}

fn configDirNameIn(
    io: std.Io,
    alloc: Allocator,
    environ_map: *const std.process.Environ.Map,
) ![]const u8 {
    inline for (.{ "wisp", "ghostty" }) |name| {
        const path = try internal_os.xdg.config(io, alloc, environ_map, .{ .subdir = name });
        defer alloc.free(path);
        const stat = std.Io.Dir.cwd().statFile(io, path, .{}) catch null;
        if (stat) |st| if (st.kind == .directory) return name;
    }
    return "wisp";
}

/// The wisp and ghostty config dirs, set only when wisp is in use and
/// a ghostty dir also exists, so the ghostty one is ignored.
pub const Shadow = struct {
    wisp: []const u8,
    ghostty: []const u8,

    pub fn deinit(self: Shadow, alloc: Allocator) void {
        alloc.free(self.wisp);
        alloc.free(self.ghostty);
    }
};

/// Returns the paths if the wisp config dir shadows a ghostty one.
/// The caller must deinit the result.
pub fn configDirShadow(
    io: std.Io,
    alloc: Allocator,
    environ_map: *const std.process.Environ.Map,
) !?Shadow {
    if (!std.mem.eql(u8, try configDirNameIn(io, alloc, environ_map), "wisp")) return null;
    const ghostty = try internal_os.xdg.config(io, alloc, environ_map, .{ .subdir = "ghostty" });
    errdefer alloc.free(ghostty);
    const stat = std.Io.Dir.cwd().statFile(io, ghostty, .{}) catch null;
    if (stat == null or stat.?.kind != .directory) {
        alloc.free(ghostty);
        return null;
    }
    return .{
        .wisp = try internal_os.xdg.config(io, alloc, environ_map, .{ .subdir = "wisp" }),
        .ghostty = ghostty,
    };
}

fn xdgConfigFile(
    io: std.Io,
    alloc: Allocator,
    environ_map: *const std.process.Environ.Map,
    name: []const u8,
) ![]const u8 {
    const subdir = try std.fs.path.join(alloc, &.{
        try configDirNameIn(io, alloc, environ_map),
        name,
    });
    defer alloc.free(subdir);
    return try internal_os.xdg.config(io, alloc, environ_map, .{ .subdir = subdir });
}

/// Default path for the XDG home configuration file. Returned value
/// must be freed by the caller.
pub fn defaultXdgPath(alloc: Allocator) ![]const u8 {
    var environ_map = try global.environMap();
    defer environ_map.deinit();
    return try xdgConfigFile(global.io(), alloc, &environ_map, "config.ghostty");
}

/// Ghostty <1.3.0 default path for the XDG home configuration file.
/// Returned value must be freed by the caller.
pub fn legacyDefaultXdgPath(alloc: Allocator) ![]const u8 {
    var environ_map = try global.environMap();
    defer environ_map.deinit();
    return try xdgConfigFile(global.io(), alloc, &environ_map, "config");
}

/// Preferred default path for the XDG home configuration file.
/// Returned value must be freed by the caller.
pub fn preferredXdgPath(alloc: Allocator) ![]const u8 {
    // If the XDG path exists, use that.
    const xdg_path = try defaultXdgPath(alloc);
    if (open(global.io(), xdg_path)) |f| {
        f.close(global.io());
        return xdg_path;
    } else |_| {}

    // Try the legacy path
    errdefer alloc.free(xdg_path);
    const legacy_xdg_path = try legacyDefaultXdgPath(alloc);
    if (open(global.io(), legacy_xdg_path)) |f| {
        f.close(global.io());
        alloc.free(xdg_path);
        return legacy_xdg_path;
    } else |_| {}

    // Legacy path and XDG path both don't exist. Return the
    // new one.
    alloc.free(legacy_xdg_path);
    return xdg_path;
}

/// Default path for the macOS Application Support configuration file.
/// Returned value must be freed by the caller.
pub fn defaultAppSupportPath(alloc: Allocator) ![]const u8 {
    return try internal_os.macos.appSupportDir(alloc, "config.ghostty");
}

/// Ghostty <1.3.0 default path for the macOS Application Support
/// configuration file. Returned value must be freed by the caller.
pub fn legacyDefaultAppSupportPath(alloc: Allocator) ![]const u8 {
    return try internal_os.macos.appSupportDir(alloc, "config");
}

/// Preferred default path for the macOS Application Support configuration file.
/// Returned value must be freed by the caller.
pub fn preferredAppSupportPath(alloc: Allocator) ![]const u8 {
    // If the app support path exists, use that.
    const app_support_path = try defaultAppSupportPath(alloc);
    if (open(global.io(), app_support_path)) |f| {
        f.close(global.io());
        return app_support_path;
    } else |_| {}

    // Try the legacy path
    errdefer alloc.free(app_support_path);
    const legacy_app_support_path = try legacyDefaultAppSupportPath(alloc);
    if (open(global.io(), legacy_app_support_path)) |f| {
        f.close(global.io());
        alloc.free(app_support_path);
        return legacy_app_support_path;
    } else |_| {}

    // Legacy path and app support path both don't exist. Return the
    // new one.
    alloc.free(legacy_app_support_path);
    return app_support_path;
}

/// Returns the path to the preferred default configuration file.
/// This is the file where users should place their configuration.
///
/// This doesn't create or populate the file with any default
/// contents; downstream callers must handle this.
///
/// The returned value must be freed by the caller.
pub fn preferredDefaultFilePath(alloc: Allocator) ![]const u8 {
    switch (builtin.target.os.tag) {
        .macos => {
            // macOS prefers the Application Support directory
            // if it exists.
            const app_support_path = try preferredAppSupportPath(alloc);
            const app_support_file = open(global.io(), app_support_path) catch {
                // Try the XDG path if it exists
                const xdg_path = try preferredXdgPath(alloc);
                const xdg_file = open(global.io(), xdg_path) catch {
                    // If neither file exists, use app support
                    alloc.free(xdg_path);
                    return app_support_path;
                };
                xdg_file.close(global.io());
                alloc.free(app_support_path);
                return xdg_path;
            };
            app_support_file.close(global.io());
            return app_support_path;
        },

        // All other platforms use XDG only
        else => return try preferredXdgPath(alloc),
    }
}

const OpenFileError = error{
    FileNotFound,
    FileIsEmpty,
    FileOpenFailed,
    NotAFile,
};

/// Opens the file at the given path and returns the file handle
/// if it exists and is non-empty. This also constrains the possible
/// errors to a smaller set that we can explicitly handle.
pub fn open(io: std.Io, path: []const u8) OpenFileError!std.Io.File {
    assert(std.fs.path.isAbsolute(path));

    var file = std.Io.Dir.openFileAbsolute(
        io,
        path,
        .{},
    ) catch |err| switch (err) {
        error.FileNotFound => return OpenFileError.FileNotFound,
        else => {
            log.warn("unexpected file open error path={s} err={}", .{
                path,
                err,
            });
            return OpenFileError.FileOpenFailed;
        },
    };
    errdefer file.close(io);

    const stat = file.stat(io) catch |err| {
        log.warn("error getting file stat path={s} err={}", .{
            path,
            err,
        });
        return OpenFileError.FileOpenFailed;
    };
    switch (stat.kind) {
        .file => {},
        else => return OpenFileError.NotAFile,
    }

    if (stat.size == 0) return OpenFileError.FileIsEmpty;

    return file;
}

fn testConfigDirName(dirs: []const []const u8, expected: []const u8) !void {
    const testing = std.testing;
    const io = testing.io;
    const alloc = testing.allocator;

    var tmp = testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    for (dirs) |d| try tmp.dir.createDir(io, d, .default_dir);
    const tmp_path = try tmp.dir.realPathFileAlloc(io, ".", alloc);
    defer alloc.free(tmp_path);

    var environ_map = try testing.environ.createMap(alloc);
    defer environ_map.deinit();
    try environ_map.put("XDG_CONFIG_HOME", tmp_path);

    try testing.expectEqualStrings(expected, try configDirNameIn(io, alloc, &environ_map));

    const path = try xdgConfigFile(io, alloc, &environ_map, "config.ghostty");
    defer alloc.free(path);
    const expected_path = try std.fs.path.join(alloc, &.{ tmp_path, expected, "config.ghostty" });
    defer alloc.free(expected_path);
    try testing.expectEqualStrings(expected_path, path);

    // Nothing is created.
    var count: usize = 0;
    var it = tmp.dir.iterate();
    while (try it.next(io)) |_| count += 1;
    try testing.expectEqual(dirs.len, count);
}

test "file_load configDirName only ghostty" {
    try testConfigDirName(&.{"ghostty"}, "ghostty");
}

test "file_load configDirName only wisp" {
    try testConfigDirName(&.{"wisp"}, "wisp");
}

test "file_load configDirName both" {
    try testConfigDirName(&.{ "wisp", "ghostty" }, "wisp");
}

test "file_load configDirName neither" {
    try testConfigDirName(&.{}, "wisp");
}

test "file_load configDirName ghostty symlink to a directory" {
    const testing = std.testing;
    const io = testing.io;
    const alloc = testing.allocator;

    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDir(io, "dotfiles", .default_dir);
    try tmp.dir.symLink(io, "dotfiles", "ghostty", .{ .is_directory = true });
    const tmp_path = try tmp.dir.realPathFileAlloc(io, ".", alloc);
    defer alloc.free(tmp_path);

    var environ_map = try testing.environ.createMap(alloc);
    defer environ_map.deinit();
    try environ_map.put("XDG_CONFIG_HOME", tmp_path);

    try testing.expectEqualStrings("ghostty", try configDirNameIn(io, alloc, &environ_map));
}
