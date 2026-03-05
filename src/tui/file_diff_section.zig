const std = @import("std");
const vaxis = @import("vaxis");
const git = @import("../models/git.zig");
const theme = @import("theme.zig");
const Section = @import("section.zig").Section;

// Build a lookup table at comptime
const diff_styles = theme.diff_line_styles{};
const diff_style_map = std.enums.directEnumArray(git.DiffLineKind, vaxis.Style, 10, .{
    .file_header = diff_styles.file,
    .hunk_header = diff_styles.hunk,
    .added = diff_styles.add,
    .removed = diff_styles.remove,
    .context = diff_styles.normal,
    .meta = diff_styles.meta,
});

fn getDiffStyle(kind: git.DiffLineKind) vaxis.Style {
    return diff_style_map[@intFromEnum(kind)];
}

fn getFileOperationSymbol(operation: git.FileOperation) []const u8 {
    return switch (operation) {
        .added => "[+]",
        .deleted => "[-]",
        .renamed => "[→]",
        .modified => "[~]",
    };
}

fn getFileOperationStyle(operation: git.FileOperation) vaxis.Style {
    const op_styles = theme.file_operation_styles{};
    return switch (operation) {
        .added => op_styles.added,
        .deleted => op_styles.deleted,
        .renamed => op_styles.renamed,
        .modified => op_styles.modified,
    };
}

pub const FileDiffSection = struct {
    base: Section,
    allocator: std.mem.Allocator,
    file_diffs: std.ArrayList(git.FileDiff),
    selected_index: usize = 0,
    scroll_offset: usize = 0,
    visible_area: usize = 10,

    pub fn create(allocator: std.mem.Allocator, file_diffs: std.ArrayList(git.FileDiff)) !*Section {
        const self = try allocator.create(@This());
        self.* = .{
            .base = .{ .vtable = &vtable, .data = self },
            .allocator = allocator,
            .file_diffs = file_diffs,
        };
        return &self.base;
    }

    fn getTotalDisplayLines(self: *@This()) usize {
        var total: usize = 0;
        for (self.file_diffs.items) |file_diff| {
            total += 1; // file header
            for (file_diff.hunks.items) |hunk| {
                total += 1; // Hunk header
                total += hunk.lines.items.len;
            }
        }
        return total;
    }

    fn getLineInfo(self: *@This(), index: usize) struct {
        text: []const u8,
        kind: ?git.DiffLineKind,
        file_operation: ?git.FileOperation = null,
    } {
        var current_idx: usize = 0;
        for (self.file_diffs.items) |file_diff| {
            const operation = file_diff.operation;
            if (current_idx == index) {
                return .{
                    .text = file_diff.file_path,
                    .kind = .file_header,
                    .file_operation = operation,
                };
            }
            current_idx += 1;
            for (file_diff.hunks.items) |hunk| {
                // Check hunk header
                if (current_idx == index) {
                    return .{
                        .text = hunk.header,
                        .kind = .hunk_header,
                    };
                }
                current_idx += 1;

                // Check lines in hunk
                for (hunk.lines.items) |line| {
                    if (current_idx == index) {
                        return .{
                            .text = line.text,
                            .kind = line.kind,
                        };
                    }
                    current_idx += 1;
                }
            }
        }
        // Return empty if index out of bounds
        return .{
            .text = "",
            .kind = null,
        };
    }

    fn handleInput(data: *anyopaque, key: vaxis.Key) void {
        const self: *@This() = @ptrCast(@alignCast(data));
        const half_page = self.visible_area / 2;
        const total_lines = self.getTotalDisplayLines();

        switch (key.codepoint) {
            'j' => {
                if (self.selected_index < total_lines - 1) {
                    self.selected_index += 1;
                    if ((self.selected_index + 1 + self.scroll_offset) % self.visible_area == 0) {
                        const new_offset = self.scroll_offset + half_page;
                        if (new_offset < total_lines - 1) {
                            self.scroll_offset = new_offset;
                        }
                    }
                }
            },
            'k' => {
                if (self.selected_index > 0) {
                    if (self.selected_index == self.scroll_offset) {
                        if (self.scroll_offset > half_page) {
                            self.scroll_offset -= half_page;
                        } else {
                            self.scroll_offset = 0;
                        }
                    }
                    self.selected_index -= 1;
                }
            },
            '\t' => {
                // Toggle hunk or file at

            },
            else => {},
        }
    }

    fn update(data: *anyopaque) !void {
        // FileDiffSection doesn't need async updates
        _ = data;
    }

    fn render(data: *anyopaque, window: vaxis.Window) !void {
        const self: *@This() = @ptrCast(@alignCast(data));
        self.visible_area = window.height;
        var segments = std.ArrayList(vaxis.Segment){};
        defer segments.deinit(self.allocator);

        const total_lines = self.getTotalDisplayLines();
        const visible = @min(
            total_lines -| self.scroll_offset,
            self.visible_area,
        );

        for (0..visible) |i| {
            const idx = self.scroll_offset + i;
            const line_info = self.getLineInfo(idx);
            const is_selected = idx == self.selected_index;

            if (line_info.kind) |kind| {
                const style = if (is_selected)
                    theme.selected_row_style
                else
                    getDiffStyle(kind);

                if (kind == .file_header or kind == .hunk_header) {
                    try segments.append(self.allocator, vaxis.Segment{
                        .text = "⌄",
                        .style = style,
                    });

                    if (line_info.file_operation) |operation| {
                        try segments.append(self.allocator, vaxis.Segment{
                            .text = getFileOperationSymbol(operation),
                            .style = getFileOperationStyle(operation),
                        });
                    }
                }

                try segments.append(self.allocator, vaxis.Segment{
                    .text = line_info.text,
                    .style = style,
                });

                // Add newline segment (except after last line)
                if (i < visible - 1) {
                    try segments.append(self.allocator, .{ .text = "\n", .style = theme.normal_style });
                }
            }
        }

        _ = window.print(segments.items, .{});
    }

    fn deinit(data: *anyopaque) void {
        const self: *@This() = @ptrCast(@alignCast(data));

        // Note: We don't own the file_diffs, just using them
        // The parent (PRDetailsScreen) will clean them up

        self.allocator.destroy(self);
    }

    const vtable = Section.VTable{
        .handleInput = handleInput,
        .update = update,
        .render = render,
        .deinit = deinit,
    };
};
