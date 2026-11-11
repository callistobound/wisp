//! Wisp release tags: `vX.Y.Z-wisp.N` builds as the stable `X.Y.Z+wisp.N`.
const std = @import("std");

/// The version for a `vX.Y.Z-wisp.N` tag, or null for any other tag.
/// X.Y.Z must match `app`, the version in build.zig.zon.
pub fn fromTag(
    tag: []const u8,
    app: std.SemanticVersion,
) error{TagVersionMismatch}!?std.SemanticVersion {
    if (tag.len == 0 or tag[0] != 'v') return null;
    const v = std.SemanticVersion.parse(tag[1..]) catch return null;
    const pre = v.pre orelse return null;
    const prefix = "wisp.";
    if (!std.mem.startsWith(u8, pre, prefix)) return null;
    const n = pre[prefix.len..];
    if (n.len == 0) return null;
    for (n) |c| if (!std.ascii.isDigit(c)) return null;
    if (v.build != null) return null;

    if (v.major != app.major or v.minor != app.minor or v.patch != app.patch)
        return error.TagVersionMismatch;

    return .{ .major = v.major, .minor = v.minor, .patch = v.patch, .build = pre };
}

test "wisp tag" {
    const app: std.SemanticVersion = .{ .major = 1, .minor = 4, .patch = 1, .pre = "dev" };
    const v = (try fromTag("v1.4.1-wisp.3", app)).?;
    try std.testing.expectEqual(@as(usize, 1), v.major);
    try std.testing.expectEqual(@as(usize, 4), v.minor);
    try std.testing.expectEqual(@as(usize, 1), v.patch);
    try std.testing.expect(v.pre == null);
    try std.testing.expectEqualStrings("wisp.3", v.build.?);
}

test "other tags are not wisp tags" {
    const app: std.SemanticVersion = .{ .major = 1, .minor = 4, .patch = 1 };
    try std.testing.expect(try fromTag("v1.4.1", app) == null);
    try std.testing.expect(try fromTag("tip", app) == null);
    try std.testing.expect(try fromTag("vt-1.0.0", app) == null);
    try std.testing.expect(try fromTag("v1.4.1-wisp.", app) == null);
    try std.testing.expect(try fromTag("v1.4.1-wisp.x", app) == null);
}

test "wisp tag must match build.zig.zon" {
    const app: std.SemanticVersion = .{ .major = 1, .minor = 4, .patch = 1 };
    try std.testing.expectError(error.TagVersionMismatch, fromTag("v1.4.0-wisp.1", app));
}
