//! Line-preserving edits of a config file. Only lines for the edited key
//! change; every other byte is copied through. Line meaning matches
//! `cli.args.LineIterator`.
const std = @import("std");
const Allocator = std.mem.Allocator;
const cli = @import("../cli.zig");

const bom = "\xEF\xBB\xBF";

pub const Entry = struct { key: []const u8, value: []const u8 };

pub const Op = union(enum) {
    /// Replace the last line for key; append if none.
    set: Entry,
    /// Remove every line for key.
    unset: []const u8,
    /// Append, even if key exists (repeatable keys).
    add: Entry,
    /// Remove every line whose key and value match.
    remove: Entry,
};

pub const Error = Allocator.Error || error{InvalidValue};

/// Apply `op` to `src`. The caller owns the result.
pub fn apply(alloc: Allocator, src: []const u8, op: Op) Error![]u8 {
    return applyInner(alloc, src, op) catch |err| switch (err) {
        // An allocating writer only fails on allocation.
        error.WriteFailed => error.OutOfMemory,
        else => |e| e,
    };
}

fn applyInner(
    alloc: Allocator,
    src: []const u8,
    op: Op,
) (Error || error{WriteFailed})![]u8 {
    const key, const entry: ?Entry = switch (op) {
        .unset => |k| .{ k, null },
        .set, .add, .remove => |e| .{ e.key, e },
    };
    if (key.len == 0 or std.mem.indexOfAny(u8, key, "=# \t\r\n") != null)
        return error.InvalidValue;
    if (entry) |e| if (std.mem.indexOfAny(u8, e.value, "\r\n") != null)
        return error.InvalidValue;

    // The line to replace for set, found up front since it's the last match.
    var target: ?usize = null;
    if (op == .set) {
        var it: LineIter = .{ .src = src };
        while (it.next()) |l| if (l.matches(key, null)) {
            target = l.start;
        };
    }

    var out: std.Io.Writer.Allocating = .init(alloc);
    errdefer out.deinit();
    const w = &out.writer;

    var it: LineIter = .{ .src = src };
    while (it.next()) |l| {
        const hit = switch (op) {
            .set => target == l.start,
            .unset => l.matches(key, null),
            .remove => |e| l.matches(key, e.value),
            .add => false,
        };
        if (!hit) {
            try w.writeAll(src[l.start..l.end]);
        } else if (op == .set) {
            try w.writeAll(src[l.start .. l.start + l.indent]);
            try writeEntry(w, op.set);
            try w.writeAll(l.ending);
        }
    }

    switch (op) {
        .set, .add => |e| if (op == .add or target == null) {
            const nl = if (std.mem.indexOf(u8, src, "\r\n") != null) "\r\n" else "\n";
            if (src.len > 0 and src[src.len - 1] != '\n') try w.writeAll(nl);
            try writeEntry(w, e);
            try w.writeAll(nl);
        },
        else => {},
    }

    return out.toOwnedSlice();
}

fn writeEntry(w: *std.Io.Writer, e: Entry) !void {
    const v = e.value;
    const quote = v.len > 0 and
        (std.mem.indexOfScalar(u8, " \t", v[0]) != null or
            std.mem.indexOfScalar(u8, " \t", v[v.len - 1]) != null) or
        (v.len >= 2 and v[0] == '"' and v[v.len - 1] == '"');
    const q = if (quote) "\"" else "";
    try w.print("{s} = {s}{s}{s}", .{ e.key, q, v, q });
}

const Line = struct {
    /// Raw line including its ending, as offsets into the source.
    start: usize,
    end: usize,
    /// Bytes of leading whitespace after any BOM, kept on replacement.
    indent: usize,
    key: []const u8,
    value: []const u8,
    /// False for blank lines and comments.
    entry: bool,
    /// "\n", "\r\n" or empty.
    ending: []const u8,

    fn matches(self: Line, key: []const u8, value: ?[]const u8) bool {
        if (!self.entry or !std.mem.eql(u8, self.key, key)) return false;
        return if (value) |v| std.mem.eql(u8, self.value, v) else true;
    }
};

const LineIter = struct {
    src: []const u8,
    pos: usize = 0,

    fn next(self: *LineIter) ?Line {
        if (self.pos >= self.src.len) return null;
        const start = self.pos;
        const nl = std.mem.indexOfScalarPos(u8, self.src, start, '\n');
        const end = if (nl) |i| i + 1 else self.src.len;
        self.pos = end;

        var body = self.src[start..end];
        var ending: []const u8 = "";
        if (nl != null) {
            body = body[0 .. body.len - 1];
            ending = "\n";
            if (body.len > 0 and body[body.len - 1] == '\r') {
                body = body[0 .. body.len - 1];
                ending = "\r\n";
            }
        }

        const skip: usize = if (start == 0 and std.mem.startsWith(u8, body, bom)) bom.len else 0;
        const text = body[skip..];
        const trim = std.mem.trim(u8, text, cli.args.whitespace ++ "\r");
        const indent = skip + (std.mem.indexOf(u8, text, trim) orelse 0);

        var line: Line = .{
            .start = start,
            .end = end,
            .indent = indent,
            .key = "",
            .value = "",
            .entry = trim.len > 0 and trim[0] != '#',
            .ending = ending,
        };
        if (!line.entry) return line;

        if (std.mem.indexOfScalar(u8, trim, '=')) |idx| {
            line.key = std.mem.trim(u8, trim[0..idx], cli.args.whitespace);
            var v = std.mem.trim(u8, trim[idx + 1 ..], cli.args.whitespace);
            if (v.len >= 2 and v[0] == '"' and v[v.len - 1] == '"') v = v[1 .. v.len - 1];
            line.value = v;
        } else line.key = trim;
        return line;
    }
};

fn expectApply(src: []const u8, op: Op, want: []const u8) !void {
    const got = try apply(std.testing.allocator, src, op);
    defer std.testing.allocator.free(got);
    try std.testing.expectEqualStrings(want, got);
}

fn set(k: []const u8, v: []const u8) Op {
    return .{ .set = .{ .key = k, .value = v } };
}

test "file_edit: set replaces last line and leaves the rest" {
    try expectApply(
        "# c\nfont-size = 12\n\n  font-size=13 \ntheme = x\n",
        set("font-size", "14"),
        "# c\nfont-size = 12\n\n  font-size = 14\ntheme = x\n",
    );
}

test "file_edit: set appends when absent" {
    try expectApply("", set("font-size", "14"), "font-size = 14\n");
    try expectApply("theme = x", set("font-size", "14"), "theme = x\nfont-size = 14\n");
    try expectApply("theme = x\n", set("font-size", "14"), "theme = x\nfont-size = 14\n");
}

test "file_edit: set ignores commented-out key" {
    try expectApply(
        "# font-size = 12\n",
        set("font-size", "14"),
        "# font-size = 12\nfont-size = 14\n",
    );
}

test "file_edit: set keeps CRLF" {
    try expectApply(
        "a = 1\r\nfont-size = 12\r\n",
        set("font-size", "14"),
        "a = 1\r\nfont-size = 14\r\n",
    );
    try expectApply("a = 1\r\n", set("b", "2"), "a = 1\r\nb = 2\r\n");
}

test "file_edit: set keeps BOM" {
    try expectApply(
        "\xEF\xBB\xBFfont-size = 12\n",
        set("font-size", "14"),
        "\xEF\xBB\xBFfont-size = 14\n",
    );
}

test "file_edit: set matches quoted and flag lines" {
    try expectApply(
        "font-family = \"Fira\"\n",
        set("font-family", "Iosevka"),
        "font-family = Iosevka\n",
    );
    try expectApply(
        "font-thicken\n",
        set("font-thicken", "false"),
        "font-thicken = false\n",
    );
}

test "file_edit: set quotes when needed" {
    try expectApply("", set("k", " x"), "k = \" x\"\n");
    try expectApply("", set("k", "\"q\""), "k = \"\"q\"\"\n");
    try std.testing.expectError(
        error.InvalidValue,
        apply(std.testing.allocator, "", set("k", "a\nb")),
    );
    try std.testing.expectError(
        error.InvalidValue,
        apply(std.testing.allocator, "", set("bad key", "v")),
    );
}

test "file_edit: unset removes every line" {
    try expectApply(
        "font-size = 12\na = 1\nfont-size = 13\n",
        .{ .unset = "font-size" },
        "a = 1\n",
    );
    try expectApply("a = 1\n", .{ .unset = "font-size" }, "a = 1\n");
}

test "file_edit: add appends even if present" {
    try expectApply(
        "keybind = a=b\n",
        .{ .add = .{ .key = "keybind", .value = "c=d" } },
        "keybind = a=b\nkeybind = c=d\n",
    );
}

test "file_edit: remove removes only matching entries" {
    try expectApply(
        "keybind = a=b\n# keybind = c=d\nkeybind = c=d\n",
        .{ .remove = .{ .key = "keybind", .value = "c=d" } },
        "keybind = a=b\n# keybind = c=d\n",
    );
}

test "file_edit: output parses back with LineIterator" {
    const cases = [_]Entry{
        .{ .key = "k", .value = " x" },
        .{ .key = "k", .value = "\"q\"" },
        .{ .key = "keybind", .value = "ctrl+a=new_tab" },
    };
    for (cases) |c| {
        const out = try apply(std.testing.allocator, "# c\n", .{ .set = c });
        defer std.testing.allocator.free(out);
        var reader: std.Io.Reader = .fixed(out);
        var iter: cli.args.LineIterator = .{ .r = &reader };
        const want = try std.fmt.allocPrint(std.testing.allocator, "--{s}={s}", .{ c.key, c.value });
        defer std.testing.allocator.free(want);
        try std.testing.expectEqualStrings(want, iter.next().?);
        try std.testing.expect(iter.next() == null);
    }
}
