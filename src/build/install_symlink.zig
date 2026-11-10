const std = @import("std");

/// Installs a symlink at `sub_path` (relative to `base`) pointing at
/// `target`, after `after` runs. std.Build has no step for this.
pub fn installSymlink(
    b: *std.Build,
    target: []const u8,
    base: std.Build.Configuration.LazyPath.Relative.Base,
    sub_path: []const u8,
    after: *std.Build.Step,
) *std.Build.Step {
    const ln = b.addSystemCommand(&.{ "/bin/ln", "-sf", target });
    ln.addDirectoryArg2(.{ .relative = .{
        .base = base,
        .sub_path = sub_path,
    } }, .{});
    ln.step.dependOn(after);
    return &ln.step;
}
