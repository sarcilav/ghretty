const std = @import("std");
const vaxis = @import("vaxis");
const Screen = @import("screen.zig").Screen;
const PR = @import("../models/pr.zig").PR;
const git = @import("../models/git.zig");
const GitHubClient = @import("../github/client.zig").GitHubClient;
const layout = @import("../tui/layout.zig");
const theme = @import("../tui/theme.zig");

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

// Now use it at runtime
pub fn getDiffStyle(kind: git.DiffLineKind) vaxis.Style {
    return diff_style_map[@intFromEnum(kind)];
}

pub const PRDetailsScreen = struct {
    base: Screen,
    allocator: std.mem.Allocator,
    github_client: *GitHubClient,
    pr_number: u32 = 0,
    pr: ?PR = null,
    selected_index: usize = 0,
    scroll_offset: usize = 0,
    visible_area: usize = 10, // use a default value that will be computed on the first render cycle
    loading: bool = true,
    err_msg: ?[]const u8 = null,
    file_diffs: std.ArrayList(git.FileDiff),
    pr_title: ?[]const u8 = null,
    pr_author: ?[]const u8 = null,

    // Helper function to get total display lines
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

    // Helper function to get line info at index
    fn getLineInfo(self: *@This(), index: usize) struct {
        text: []const u8,
        kind: ?git.DiffLineKind,
    } {
        var current_idx: usize = 0;
        for (self.file_diffs.items) |file_diff| {
            if (current_idx == index) {
                return .{ .text = file_diff.file_path, .kind = .file_header };
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

    pub fn create(allocator: std.mem.Allocator, pr_number: u32) !*Screen {
        const self = try allocator.create(@This());

        const github_client = try allocator.create(GitHubClient);
        github_client.* = GitHubClient.init(allocator);

        const file_diffs = std.ArrayList(git.FileDiff){};

        self.* = .{
            .base = .{ .vtable = &vtable },
            .allocator = allocator,
            .github_client = github_client,
            .pr_number = pr_number,
            .file_diffs = file_diffs,
        };
        return &self.base;
    }

    pub fn deinit(screen: *Screen) void {
        const self = fromBase(screen);

        // Clean up file_diffs
        for (self.file_diffs.items) |*file_diff| {
            file_diff.deinit(self.allocator);
        }
        self.file_diffs.deinit(self.allocator);

        if (self.pr_title) |title| self.allocator.free(title);
        if (self.pr_author) |author| self.allocator.free(author);
        if (self.pr) |*pr| pr.deinit(self.allocator);

        self.allocator.destroy(self.github_client);
        self.allocator.destroy(self);
    }

    pub fn navigateInto(screen: *Screen) !*Screen {
        const self = fromBase(screen);
        return &self.base;
    }
    pub fn handleInput(screen: *Screen, key: vaxis.Key) !void {
        const self = fromBase(screen);
        const half_page = self.visible_area / 2;
        const total_lines = self.getTotalDisplayLines();
        switch (key.codepoint) {
            'j' => {
                if (self.selected_index < total_lines - 1) {
                    // avoids infinite scrolling off the window
                    self.selected_index += 1;
                    // if we are at the bottom of visible area
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
            '\t' => {},
            'r' => {
                self.loading = true;
                self.err_msg = null;
                try self.loadPRDetails();
            },
            else => {},
        }
    }

    fn update(screen: *Screen) !void {
        const self = fromBase(screen);

        if (self.loading) {
            try self.loadPRDetails();
        }
    }

    fn loadPRDetails(self: *@This()) !void {
        defer self.loading = false;

        // Clean up file_diffs
        for (self.file_diffs.items) |*file_diff| {
            file_diff.deinit(self.allocator);
        }
        self.file_diffs.deinit(self.allocator);

        if (self.pr_title) |title| self.allocator.free(title);
        if (self.pr_author) |author| self.allocator.free(author);
        if (self.pr) |*pr| pr.deinit(self.allocator);

        const fetched_pr = self.github_client.fetchPRDetails(self.pr_number) catch |err| {
            self.err_msg = switch (err) {
                error.GhCommandFailed => "GitHub CLI command failed. Make sure 'gh' is installed and authenticated.",
                error.MissingField => "Invalid response from GitHub API.",
                else => "Unknown error fetching PRs.",
            };
            return;
        };

        self.pr = fetched_pr;

        // Get file-organized diffs with hunks
        self.file_diffs = try self.github_client.fetchPRDiff(self.pr.?);

        self.pr_title = try std.fmt.allocPrint(
            self.allocator,
            "PR #{}: {s}",
            .{ self.pr_number, self.pr.?.title },
        );

        self.pr_author = try std.fmt.allocPrint(
            self.allocator,
            "\nAuthor: @{s}",
            .{self.pr.?.author},
        );
        self.scroll_offset = 0;
        self.selected_index = 0;
    }

    pub fn render(screen: *Screen, window: vaxis.Window) !void {
        const self = fromBase(screen);
        window.clear();

        const w = window.width;
        const h = window.height;

        // --- Header ---
        var header = window.child(layout.rect(
            0,
            0,
            w,
            4,
        ));

        // --- Content ---
        var content = window.child(layout.rect(
            0,
            4,
            w,
            h - 8,
        ));
        self.visible_area = content.height;

        // --- Footer ---
        var footer = window.child(layout.rect(
            0,
            h - 4,
            w,
            4,
        ));

        _ = header.print(&.{
            .{
                .text = self.pr_title.?,
            },
        }, .{});

        _ = header.print(&.{
            .{
                .text = self.pr_author.?,
            },
        }, .{});

        // =====================
        // Loading state
        // =====================
        if (self.loading) {
            _ = content.print(&.{
                .{ .text = "Loading PR..." },
            }, .{});
            return;
        }

        // =====================
        // Error state
        // =====================
        if (self.err_msg) |err| {
            _ = content.print(&.{
                .{ .text = "Error: " },
                .{ .text = err },
            }, .{});
            return;
        }

        var segments = std.ArrayList(vaxis.Segment){};
        defer segments.deinit(self.allocator);

        const total_lines = self.getTotalDisplayLines();
        const visible = @min(
            total_lines -| self.scroll_offset,
            content.height,
        );

        for (0..visible) |i| {
            const idx = self.scroll_offset + i;
            const line_info = self.getLineInfo(idx);
            const is_selected = idx == self.selected_index;

            const style = if (is_selected)
                theme.selected_row_style
            else
                getDiffStyle(line_info.kind.?);

            if (line_info.kind) |kind| {
                if (kind == .file_header or kind == .hunk_header)
                    try segments.append(self.allocator, vaxis.Segment{
                        .text = ">",
                        .style = style,
                    });
            }

            const segment = vaxis.Segment{
                .text = line_info.text,
                .style = style,
            };

            try segments.append(self.allocator, segment);

            // Add newline segment (except after last line)
            if (i < visible - 1) {
                try segments.append(self.allocator, .{ .text = "\n", .style = theme.normal_style });
            }
        }

        _ = content.print(segments.items, .{});

        // =====================
        // Footer
        // =====================
        _ = footer.print(&.{
            .{ .text = "j/k: navigate • Enter: open • r: refresh • q: back • ctrl-q: quit" },
        }, .{});
    }

    fn fromBase(screen: *Screen) *@This() {
        return @fieldParentPtr("base", screen);
    }

    const vtable = Screen.VTable{
        .navigateInto = navigateInto,
        .handleInput = handleInput,
        .update = update,
        .render = render,
        .deinit = deinit,
    };
};
