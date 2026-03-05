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

pub const Hunk = struct {
    header: []const u8, // The "@@ -x,y +a,b @@" line
    lines: std.ArrayList(DiffLine),
    collapsed: bool = false,

    pub fn deinit(self: *Hunk, allocator: std.mem.Allocator) void {
        allocator.free(self.header);
        for (self.lines.items) |line| {
            allocator.free(line.text);
        }
        self.lines.deinit(allocator);
    }
};

pub const FileOperation = enum {
    added,
    deleted,
    renamed,
    modified,
};

pub const FileDiff = struct {
    file_path: []const u8,
    hunks: std.ArrayList(Hunk),
    collapsed: bool = true,
    operation: FileOperation = .modified, // NEW: default to modified

    pub fn deinit(self: *FileDiff, allocator: std.mem.Allocator) void {
        allocator.free(self.file_path);
        for (self.hunks.items) |*hunk| {
            hunk.deinit(allocator);
        }
        self.hunks.deinit(allocator);
    }
};

// Helper function to parse file operation from diff lines
pub fn parseFileOperation(diff_lines: []const []const u8) FileOperation {
    var old_path: ?[]const u8 = null;
    var new_path: ?[]const u8 = null;
    var has_rename_from = false;
    var has_rename_to = false;

    for (diff_lines) |line| {
        // Check for diff --git line
        if (std.mem.startsWith(u8, line, "diff --git")) {
            // Parse the diff --git line to get old and new file paths
            // Format: diff --git a/old/path b/new/path

            // Find old and new file markers
            if (std.mem.indexOf(u8, line, " a/")) |a_pos| {
                if (std.mem.indexOf(u8, line, " b/")) |b_pos| {
                    const old_path_start = a_pos + 3; // Skip " a/"
                    const new_path_start = b_pos + 3; // Skip " b/"

                    // Extract paths
                    old_path = std.mem.trim(u8, line[old_path_start..b_pos], " \t");
                    new_path = std.mem.trim(u8, line[new_path_start..], " \t");
                }
            }
        }

        // Check for rename markers
        if (std.mem.startsWith(u8, line, "rename from")) {
            has_rename_from = true;
        }
        if (std.mem.startsWith(u8, line, "rename to")) {
            has_rename_to = true;
        }

        // Check for new/deleted file mode
        if (std.mem.startsWith(u8, line, "new file mode")) {
            return .added;
        }
        if (std.mem.startsWith(u8, line, "deleted file mode")) {
            return .deleted;
        }
    }

    // Check for /dev/null paths which indicate added/deleted files
    if (old_path != null and new_path != null) {
        const is_old_null = std.mem.eql(u8, old_path.?, "/dev/null");
        const is_new_null = std.mem.eql(u8, new_path.?, "/dev/null");

        if (is_old_null and !is_new_null) {
            return .added;
        } else if (!is_old_null and is_new_null) {
            return .deleted;
        } else if (has_rename_from and has_rename_to) {
            return .renamed;
        } else if (!std.mem.eql(u8, old_path.?, new_path.?)) {
            return .renamed;
        }
    }

    return .modified; // Default if we can't determine
}

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
        std.mem.startsWith(u8, line, "+++") or
        std.mem.startsWith(u8, line, "new file mode") or
        std.mem.startsWith(u8, line, "deleted file mode") or
        std.mem.startsWith(u8, line, "rename from") or
        std.mem.startsWith(u8, line, "rename to") or
        std.mem.startsWith(u8, line, "similarity index") or
        std.mem.startsWith(u8, line, "Binary files"))
        return .meta;

    return .context;
}
