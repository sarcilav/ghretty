const std = @import("std");
const vaxis = @import("vaxis");
const PR = @import("../models/pr.zig").PR;
const theme = @import("theme.zig");

pub fn statusText(pr: PR) []const u8 {
    return switch (pr.state) {
        .open => " OPEN",
        .closed => "󰅙 CLOSED",
        .merged => " MERGED",
    };
}

pub fn statusStyle(pr: PR) vaxis.Style {
    return switch (pr.state) {
        .open => theme.success_style,
        .closed => theme.danger_style,
        .merged => theme.pr_number_style,
    };
}

pub fn lifecycleText(pr: PR) []const u8 {
    return if (pr.is_draft) " DRAFT" else " READY";
}

pub fn lifecycleStyle(pr: PR) vaxis.Style {
    return if (pr.is_draft) theme.warning_style else theme.success_style;
}

pub fn reviewText(pr: PR) []const u8 {
    return if (pr.review_requested) "review requested" else "no review requested";
}

pub fn allocStatusBadge(allocator: std.mem.Allocator, pr: PR) ![]u8 {
    return std.fmt.allocPrint(allocator, "[{s}]", .{statusText(pr)});
}

pub fn allocBodyPreview(allocator: std.mem.Allocator, pr: PR, max_len: usize) !?[]u8 {
    const body = pr.body orelse return null;

    var cleaned = std.ArrayList(u8){};
    defer cleaned.deinit(allocator);

    var saw_content = false;
    for (body) |ch| {
        const normalized = switch (ch) {
            '\n', '\r', '\t' => ' ',
            else => ch,
        };

        if (std.ascii.isWhitespace(normalized)) {
            if (!saw_content) continue;
            if (cleaned.items.len > 0 and cleaned.items[cleaned.items.len - 1] == ' ') continue;
            try cleaned.append(allocator, ' ');
        } else {
            saw_content = true;
            try cleaned.append(allocator, normalized);
        }
    }

    const trimmed = std.mem.trim(u8, cleaned.items, " ");
    if (trimmed.len == 0) return null;

    if (trimmed.len <= max_len) {
        return try allocator.dupe(u8, trimmed);
    }

    const preview_len = max_len -| 3;
    return try std.fmt.allocPrint(allocator, "{s}...", .{trimmed[0..preview_len]});
}

pub fn allocFileSummary(allocator: std.mem.Allocator, pr: PR) !?[]u8 {
    const files = pr.files orelse return null;

    var additions: u32 = 0;
    var deletions: u32 = 0;
    for (files.items) |file| {
        additions += file.additions;
        deletions += file.deletions;
    }

    return try std.fmt.allocPrint(
        allocator,
        "{} files  •  +{} -{}",
        .{ files.items.len, additions, deletions },
    );
}
