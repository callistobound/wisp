const std = @import("std");
const builtin = @import("builtin");
const assert = @import("../quirks.zig").inlineAssert;
const args = @import("args.zig");
const Allocator = std.mem.Allocator;
const Action = @import("ghostty.zig").Action;
const configpkg = @import("../config.zig");
const internal_os = @import("../os/main.zig");
const Config = configpkg.Config;
const global = @import("../global.zig");
const file_edit = configpkg.file_edit;
const Key = @import("../config/key.zig").Key;

pub const Options = struct {
    set: ?[:0]const u8 = null,
    unset: ?[:0]const u8 = null,
    add: ?[:0]const u8 = null,
    remove: ?[:0]const u8 = null,
    file: ?[:0]const u8 = null,

    _arena: ?std.heap.ArenaAllocator = null,

    pub fn deinit(self: Options) void {
        if (self._arena) |arena| arena.deinit();
    }

    /// Enables `-h` and `--help` to work.
    pub fn help(self: Options) !void {
        _ = self;
        return Action.help_error;
    }
};

/// The `edit-config` command opens the Wisp configuration file in the
/// editor specified by the `$VISUAL` or `$EDITOR` environment variables.
///
/// IMPORTANT: This command will not reload the configuration after
/// editing. You will need to manually reload the configuration using the
/// application menu, configured keybind, or by restarting Wisp. We
/// plan to auto-reload in the future, but Wisp isn't capable of
/// this yet.
///
/// The filepath opened is the default user-specific configuration
/// file, which is typically located at `$XDG_CONFIG_HOME/wisp/config.ghostty`,
/// or under `$XDG_CONFIG_HOME/ghostty` if only that directory exists.
/// On macOS, this may also be located at
/// `~/Library/Application Support/com.callistobound.wisp/config.ghostty`.
/// On macOS, whichever path exists and is non-empty will be prioritized,
/// prioritizing the Application Support directory if neither are
/// non-empty.
///
/// The flags below edit the config file in place and keep everything else
/// in it, and they don't open an editor.
///
/// Flags:
///
///   * `--set=key=value`: Set an option, replacing its last line in the file.
///     Repeatable options like `keybind` need `--add` or `--remove` instead.
///   * `--unset=key`: Remove every line for an option.
///   * `--add=key=value`: Append a line, for repeatable options like `keybind`.
///   * `--remove=key=value`: Remove the lines matching an option and value.
///   * `--file=path`: Edit this file instead of the default config file.
///
/// This command prefers the `$VISUAL` environment variable over `$EDITOR`,
/// if both are set. If neither are set, it will print an error
/// and exit.
pub fn run(alloc: Allocator) !u8 {
    // Implementation note (by @mitchellh): I do proper memory cleanup
    // throughout this command, even though we plan on doing `exec`.
    // I do this out of good hygiene in case we ever change this to
    // not using `exec` anymore and because this command isn't performance
    // critical where setting up the defer cleanup is a problem.

    var buffer: [1024]u8 = undefined;
    var stderr_writer = std.Io.File.stderr().writer(global.io(), &buffer);
    const stderr = &stderr_writer.interface;

    var opts: Options = .{};
    defer opts.deinit();

    {
        var iter = try args.argsIterator(alloc, global.args());
        defer iter.deinit();
        try args.parse(Options, alloc, &opts, &iter);
    }

    const result = runInner(alloc, opts, stderr);
    // Flushing *shouldn't* fail but...
    stderr.flush() catch {};
    return result;
}

const ResolveError = Allocator.Error || error{
    MultipleOps,
    MissingValue,
    UnknownKey,
    InvalidValue,
    RepeatableKey,
};

/// Turn the op flags into an edit. Null if none are set. The result
/// borrows from `opts`.
fn resolveOp(alloc: Allocator, opts: Options) ResolveError!?file_edit.Op {
    const flags = [_]?[:0]const u8{ opts.set, opts.unset, opts.add, opts.remove };
    var n: usize = 0;
    for (flags) |f| {
        if (f != null) n += 1;
    }
    if (n == 0) return null;
    if (n > 1) return error.MultipleOps;

    if (opts.unset) |key| {
        const op: file_edit.Op = .{ .unset = key };
        try file_edit.validate(alloc, op);
        return op;
    }

    const raw = opts.set orelse opts.add orelse opts.remove.?;
    const idx = std.mem.indexOfScalar(u8, raw, '=') orelse return error.MissingValue;
    const entry: file_edit.Entry = .{ .key = raw[0..idx], .value = raw[idx + 1 ..] };
    const op: file_edit.Op = if (opts.set != null)
        .{ .set = entry }
    else if (opts.add != null)
        .{ .add = entry }
    else
        .{ .remove = entry };
    try file_edit.validate(alloc, op);
    return op;
}

fn runOp(
    alloc: Allocator,
    opts: Options,
    op: file_edit.Op,
    stderr: *std.Io.Writer,
) !u8 {
    // openPath returns [:0]; dupe so every branch frees as a plain slice.
    const path: []u8 = try filePath(alloc, opts) orelse path: {
        const p = try configpkg.edit.openPath(alloc);
        defer alloc.free(p);
        break :path try alloc.dupe(u8, p);
    };
    defer alloc.free(path);

    file_edit.applyToFile(global.io(), alloc, path, op) catch |err| switch (err) {
        error.DanglingSymlink => {
            try stderr.print("error: {s} is a symlink to a missing file\n", .{path});
            return 1;
        },
        error.HardLink => {
            try stderr.print("error: {s} has multiple hard links; edit it directly\n", .{path});
            return 1;
        },
        error.AccessDenied, error.ReadOnlyFileSystem => {
            try stderr.print("error: cannot write {s}\n", .{path});
            return 1;
        },
        error.InvalidValue => {
            const e = switch (op) {
                .set, .add, .remove => |e| e,
                .unset => |k| file_edit.Entry{ .key = k, .value = "" },
            };
            try stderr.print("error: invalid value for {s}: {s}\n", .{ e.key, e.value });
            return 1;
        },
        else => return err,
    };
    return 0;
}

/// The absolute path for `--file`, or null if it isn't set.
fn filePath(alloc: Allocator, opts: Options) !?[]u8 {
    const f = opts.file orelse return null;
    if (std.fs.path.isAbsolute(f)) return try alloc.dupe(u8, f);
    const cwd = try cwdPath(alloc);
    defer alloc.free(cwd);
    return try std.fs.path.resolve(alloc, &.{ cwd, f });
}

fn cwdPath(alloc: Allocator) ![]u8 {
    var buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const n = try std.Io.Dir.cwd().realPathFile(global.io(), ".", &buf);
    return try alloc.dupe(u8, buf[0..n]);
}

fn runInner(alloc: Allocator, opts: Options, stderr: *std.Io.Writer) !u8 {
    const op = resolveOp(alloc, opts) catch |err| {
        switch (err) {
            error.OutOfMemory => return err,
            error.MultipleOps => try stderr.print("error: only one of --set, --unset, --add, --remove may be used\n", .{}),
            error.MissingValue => try stderr.print("error: expected key=value\n", .{}),
            error.UnknownKey => {
                const raw = opts.set orelse opts.unset orelse opts.add orelse opts.remove.?;
                const key = if (opts.unset != null) raw else raw[0 .. std.mem.indexOfScalar(u8, raw, '=') orelse raw.len];
                try stderr.print("error: unknown config option: {s}\n", .{key});
            },
            error.InvalidValue => {
                const raw = opts.set orelse opts.add orelse opts.remove.?;
                const idx = std.mem.indexOfScalar(u8, raw, '=').?;
                try stderr.print("error: invalid value for {s}: {s}\n", .{ raw[0..idx], raw[idx + 1 ..] });
            },
            error.RepeatableKey => {
                const raw = opts.set.?;
                const key = raw[0..std.mem.indexOfScalar(u8, raw, '=').?];
                try stderr.print("error: {s} can be repeated; use --add, --remove or --unset\n", .{key});
            },
        }
        return 1;
    };
    if (op) |o| return runOp(alloc, opts, o, stderr);

    // We require libc because we want to use std.c.environ for envp
    // and not have to build that ourselves. We can remove this
    // limitation later but Ghostty already heavily requires libc
    // so this is not a big deal.
    comptime assert(builtin.link_libc);

    // We load the configuration once because that will write our
    // default configuration files to disk. We don't use the config.
    var config = try Config.load(alloc);
    defer config.deinit();

    // Find the preferred path.
    const path = try filePath(alloc, opts) orelse try configpkg.preferredDefaultFilePath(alloc);
    defer alloc.free(path);

    // We don't currently support Windows because we use the exec syscall.
    if (comptime builtin.target.os.tag == .windows) {
        try stderr.print(
            \\The `wisp +edit-config` command is not supported on Windows.
            \\Please edit the configuration file manually at the following path:
            \\
            \\
        ,
            .{},
        );
        return 1;
    }

    const command = internal_os.getConfigEditCommand(alloc, path, .{ .default_editor = .failure }) catch |err| {
        switch (err) {
            error.NoEditorConfigured => {
                try stderr.print(
                    \\The $EDITOR or $VISUAL environment variable is not set or is empty.
                    \\This environment variable is required to edit the Wisp configuration
                    \\via this CLI command.
                    \\
                    \\Please set the environment variable to your preferred terminal
                    \\text editor and try again.
                    \\
                    \\If you prefer to edit the configuration file another way,
                    \\you can find the configuration file at the following path:
                    \\
                    \\
                ,
                    .{},
                );

                // Output the path using the OSC8 sequence so that it is linked.
                try stderr.print(
                    "\x1b]8;;file://{s}\x1b\\{s}\x1b]8;;\x1b\\\n",
                    .{ path, path },
                );

                return 1;
            },
            error.WriteFailed,
            error.OutOfMemory,
            => |e| return e,
        }
    };
    defer alloc.free(command);

    // Run/replace process (using execve)
    const argv = [_:null]?[*:0]const u8{
        "/bin/sh",
        "-c",
        command.ptr,
    };
    const envp = std.c.environ;
    const err = std.posix.errno(std.posix.system.execve(argv[0].?, &argv, envp));

    // If we reached this point then exec failed.
    try stderr.print(
        \\Failed to execute the editor (E{t}).
        \\
        \\This is usually due to the executable path not existing, invalid
        \\permissions, or the shell environment not being set up
        \\correctly.
        \\
        \\Command: {s}
        \\
    , .{
        err,
        command,
    });
    // Output the path using the OSC8 sequence so that it is linked.
    try stderr.print(
        "Path: \x1b]8;;file://{s}\x1b\\{s}\x1b]8;;\x1b\\\n",
        .{ path, path },
    );
    return 1;
}

test "resolveOp" {
    const testing = std.testing;
    const alloc = testing.allocator;

    try testing.expect((try resolveOp(alloc, .{})) == null);

    const set = (try resolveOp(alloc, .{ .set = "font-size=14" })).?;
    try testing.expectEqualStrings("font-size", set.set.key);
    try testing.expectEqualStrings("14", set.set.value);

    const add = (try resolveOp(alloc, .{ .add = "keybind=ctrl+a=new_tab" })).?;
    try testing.expectEqualStrings("keybind", add.add.key);
    try testing.expectEqualStrings("ctrl+a=new_tab", add.add.value);

    const unset = (try resolveOp(alloc, .{ .unset = "font-size" })).?;
    try testing.expectEqualStrings("font-size", unset.unset);

    try testing.expectError(error.MultipleOps, resolveOp(alloc, .{ .set = "font-size=14", .unset = "font-size" }));
    try testing.expectError(error.MissingValue, resolveOp(alloc, .{ .set = "font-size" }));
    try testing.expectError(error.UnknownKey, resolveOp(alloc, .{ .set = "nope=1" }));
    try testing.expectError(error.InvalidValue, resolveOp(alloc, .{ .set = "font-size=abc" }));
    try testing.expectError(error.RepeatableKey, resolveOp(alloc, .{ .set = "keybind=ctrl+a=new_tab" }));
    try testing.expectError(error.RepeatableKey, resolveOp(alloc, .{ .set = "palette=1=#ff0000" }));
}

test "filePath" {
    const testing = std.testing;
    const alloc = testing.allocator;

    try testing.expect((try filePath(alloc, .{})) == null);

    const abs = if (comptime builtin.os.tag == .windows) "C:\\x\\config" else "/x/config";
    const got_abs = (try filePath(alloc, .{ .file = abs })).?;
    defer alloc.free(got_abs);
    try testing.expectEqualStrings(abs, got_abs);

    const got_rel = (try filePath(alloc, .{ .file = "config" })).?;
    defer alloc.free(got_rel);
    try testing.expect(std.fs.path.isAbsolute(got_rel));
    try testing.expectEqualStrings("config", std.fs.path.basename(got_rel));
}
