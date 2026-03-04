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
    loading: bool = true,
    err_msg: ?[]const u8 = null,
    diff_lines: std.ArrayList(git.DiffLine),
    pr_title: ?[]const u8 = null,
    pr_author: ?[]const u8 = null,

    pub fn create(allocator: std.mem.Allocator, pr_number: u32) !*Screen {
        const self = try allocator.create(@This());

        const github_client = try allocator.create(GitHubClient);
        github_client.* = GitHubClient.init(allocator);

        const diff_lines = std.ArrayList(git.DiffLine){};
        self.* = .{
            .base = .{ .vtable = &vtable },
            .allocator = allocator,
            .github_client = github_client,
            .pr_number = pr_number,
            .diff_lines = diff_lines,
        };
        return &self.base;
    }

    pub fn deinit(screen: *Screen) void {
        const self = fromBase(screen);
        for (self.diff_lines.items) |line| {
            self.allocator.free(line.text);
        }
        self.diff_lines.deinit(self.allocator);

        if(self.pr_title) |title| self.allocator.free(title);
        if(self.pr_author) |author| self.allocator.free(author);
        if(self.pr) |*pr| pr.deinit(self.allocator);

        self.allocator.destroy(self.github_client);
        self.allocator.destroy(self);
    }

    pub fn navigateInto(screen: *Screen) !*Screen {
        const self = fromBase(screen);
        return &self.base;
    }
    pub fn handleInput(screen: *Screen, key: vaxis.Key) !void {
        const self = fromBase(screen);

        switch (key.codepoint) {
            'j' => {
                if(self.selected_index < self.diff_lines.items.len - 1 ) {
                    // avoids infinite scrolling off the window, but it will be nicer to avoid getting out of the screen, for now it is fine
                    self.selected_index += 1;
                }
            },
            'k' => {
                if (self.selected_index > 0) {
                    self.selected_index -= 1;
                }
            },
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

        // avoid leaking previous allocations
        for (self.diff_lines.items) |line| {
            self.allocator.free(line.text);
        }
        self.diff_lines.deinit(self.allocator);

        if(self.pr_title) |title| self.allocator.free(title);
        if(self.pr_author) |author| self.allocator.free(author);
        if(self.pr) |*pr| pr.deinit(self.allocator);

        const fetched_pr = self.github_client.fetchPRDetails(self.pr_number) catch |err| {
            self.err_msg = switch (err) {
                error.GhCommandFailed => "GitHub CLI command failed. Make sure 'gh' is installed and authenticated.",
                error.MissingField => "Invalid response from GitHub API.",
                else => "Unknown error fetching PRs.",
            };
            return;
        };

        self.pr = fetched_pr;

        // TODO handle fetchPRDiff errors
        self.diff_lines = try self.github_client.fetchPRDiff(self.pr.?);

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
        // TODO: Draw PR description and comments
        const visible = @min(
            self.diff_lines.items.len -| self.scroll_offset,
            content.height,
        );

        var segments = std.ArrayList(vaxis.Segment){};
        defer segments.deinit(self.allocator);

        for (0..visible) |i| {
            const idx = self.scroll_offset + i;
            const diff_line = self.diff_lines.items[idx];
            const is_selected = idx == self.selected_index;

            const segment = vaxis.Segment{
                .text = diff_line.text,
                .style = if (is_selected) theme.selected_row_style else getDiffStyle(diff_line.kind),
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
            .{ .text = "j/k: navigate • Enter: open • r: refresh • q: back" },
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
