//! Wisp environment variables. Reads prefer `WISP_<suffix>` and fall back
//! to `GHOSTTY_<suffix>`.
const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;
const Environ = std.process.Environ;

/// Returns `WISP_<suffix>`, else `GHOSTTY_<suffix>`, else null.
pub fn get(env: *const Environ.Map, comptime suffix: []const u8) ?[]const u8 {
    return env.get("WISP_" ++ suffix) orelse env.get("GHOSTTY_" ++ suffix);
}

/// Same order as `get`, with `Environ.getAlloc` semantics.
pub fn getAlloc(
    environ: Environ,
    alloc: Allocator,
    comptime suffix: []const u8,
) Environ.GetAllocError![]u8 {
    return environ.getAlloc(alloc, "WISP_" ++ suffix) catch |err| switch (err) {
        error.EnvironmentVariableMissing => environ.getAlloc(alloc, "GHOSTTY_" ++ suffix),
        else => err,
    };
}

/// Same order as `get`, with `Environ.getPosix` semantics.
pub fn getPosix(environ: Environ, comptime suffix: []const u8) ?[:0]const u8 {
    return environ.getPosix("WISP_" ++ suffix) orelse environ.getPosix("GHOSTTY_" ++ suffix);
}

/// Sets `WISP_<suffix>` and `GHOSTTY_<suffix>` for public variables.
pub fn putPublic(
    env: *Environ.Map,
    comptime suffix: []const u8,
    value: []const u8,
) Allocator.Error!void {
    try env.put("WISP_" ++ suffix, value);
    try env.put("GHOSTTY_" ++ suffix, value);
}

/// Sets only `WISP_<suffix>`, for private shell-integration handoff.
pub fn putPrivate(
    env: *Environ.Map,
    comptime suffix: []const u8,
    value: []const u8,
) Allocator.Error!void {
    try env.put("WISP_" ++ suffix, value);
}

/// Removes `WISP_<suffix>` and `GHOSTTY_<suffix>`.
pub fn remove(env: *Environ.Map, comptime suffix: []const u8) void {
    _ = env.orderedRemove("WISP_" ++ suffix);
    _ = env.orderedRemove("GHOSTTY_" ++ suffix);
}

test "wisp_env: get" {
    const testing = std.testing;
    var env: Environ.Map = .init(testing.allocator);
    defer env.deinit();

    try testing.expect(get(&env, "TEST") == null);

    try env.put("GHOSTTY_TEST", "ghostty");
    try testing.expectEqualStrings("ghostty", get(&env, "TEST").?);

    try env.put("WISP_TEST", "wisp");
    try testing.expectEqualStrings("wisp", get(&env, "TEST").?);

    // An empty WISP_ value still wins.
    try env.put("WISP_TEST", "");
    try testing.expectEqualStrings("", get(&env, "TEST").?);
}

test "wisp_env: getAlloc and getPosix" {
    if (Environ.Block != Environ.PosixBlock) return error.SkipZigTest;

    const testing = std.testing;
    const alloc = testing.allocator;
    var map: Environ.Map = .init(alloc);
    defer map.deinit();

    {
        const block = try map.createPosixBlock(alloc, .{});
        defer block.deinit(alloc);
        const environ: Environ = .{ .block = block };
        try testing.expectError(
            error.EnvironmentVariableMissing,
            getAlloc(environ, alloc, "TEST"),
        );
        try testing.expect(getPosix(environ, "TEST") == null);
    }

    try map.put("GHOSTTY_TEST", "ghostty");
    {
        const block = try map.createPosixBlock(alloc, .{});
        defer block.deinit(alloc);
        const environ: Environ = .{ .block = block };
        const v = try getAlloc(environ, alloc, "TEST");
        defer alloc.free(v);
        try testing.expectEqualStrings("ghostty", v);
        try testing.expectEqualStrings("ghostty", getPosix(environ, "TEST").?);
    }

    try map.put("WISP_TEST", "wisp");
    {
        const block = try map.createPosixBlock(alloc, .{});
        defer block.deinit(alloc);
        const environ: Environ = .{ .block = block };
        const v = try getAlloc(environ, alloc, "TEST");
        defer alloc.free(v);
        try testing.expectEqualStrings("wisp", v);
        try testing.expectEqualStrings("wisp", getPosix(environ, "TEST").?);
    }
}

test "wisp_env: putPublic" {
    const testing = std.testing;
    var env: Environ.Map = .init(testing.allocator);
    defer env.deinit();

    try putPublic(&env, "TEST", "v");
    try testing.expectEqualStrings("v", env.get("WISP_TEST").?);
    try testing.expectEqualStrings("v", env.get("GHOSTTY_TEST").?);
}

test "wisp_env: putPrivate" {
    const testing = std.testing;
    var env: Environ.Map = .init(testing.allocator);
    defer env.deinit();

    try putPrivate(&env, "TEST", "v");
    try testing.expectEqualStrings("v", env.get("WISP_TEST").?);
    try testing.expect(env.get("GHOSTTY_TEST") == null);
}

test "wisp_env: remove" {
    const testing = std.testing;
    var env: Environ.Map = .init(testing.allocator);
    defer env.deinit();

    try env.put("WISP_TEST", "a");
    try env.put("GHOSTTY_TEST", "b");
    try env.put("OTHER", "c");
    remove(&env, "TEST");
    try testing.expect(env.get("WISP_TEST") == null);
    try testing.expect(env.get("GHOSTTY_TEST") == null);
    try testing.expectEqualStrings("c", env.get("OTHER").?);
}
