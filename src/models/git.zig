const std = @import("std");

pub const DiffLineKind = enum {
    file_header,
    hunk_header,
    added,
    removed,
    context,
    meta,
};

pub const DiffLine = struct {
    kind: DiffLineKind,
    text: []const u8, // slice into raw patch
};

pub fn classify(line: []const u8) DiffLineKind {
    if (std.mem.startsWith(u8, line, "diff --git"))
        return .file_header;

    if (std.mem.startsWith(u8, line, "@@"))
        return .hunk_header;

    if (std.mem.startsWith(u8, line, "+") and
        !std.mem.startsWith(u8, line, "+++"))
        return .added;

    if (std.mem.startsWith(u8, line, "-") and
        !std.mem.startsWith(u8, line, "---"))
        return .removed;

    if (std.mem.startsWith(u8, line, "index") or
        std.mem.startsWith(u8, line, "---") or
        std.mem.startsWith(u8, line, "+++"))
        return .meta;

    return .context;
}
