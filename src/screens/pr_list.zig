const std = @import("std");
const vaxis = @import("vaxis");
const Screen = @import("screen.zig").Screen;
const PRDetailsScreen = @import("pr_details.zig").PRDetailsScreen;
const PR = @import("../models/pr.zig").PR;
const GitHubClient = @import("../github/client.zig").GitHubClient;
const layout = @import("../tui/layout.zig");
const pr_presentation = @import("../tui/pr_presentation.zig");
const theme = @import("../tui/theme.zig");
const help_modal = @import("../tui/help_modal.zig");

pub const PRListScreen = struct {
    base: Screen,
    allocator: std.mem.Allocator,
    github_client: *GitHubClient,
    prs: std.ArrayList(PR),
    selected_index: usize = 0,
    offset: usize = 0,
    loading: bool = true,
    err_msg: ?[]const u8 = null,
    visible_pr_elements: std.ArrayListUnmanaged([]u8),

    pub fn create(allocator: std.mem.Allocator) !*Screen {
        const self = try allocator.create(@This());

        const github_client = try allocator.create(GitHubClient);

        github_client.* = GitHubClient.init(allocator);

        const prs = std.ArrayList(PR){};
        const visible_pr_elements = std.ArrayListUnmanaged([]u8){};

        self.* = .{
            .base = .{ .vtable = &vtable },
            .allocator = allocator,
            .github_client = github_client,
            .prs = prs,
            .visible_pr_elements = visible_pr_elements,
        };

        return &self.base;
    }

    fn deinit(screen: *Screen) void {
        const self = fromBase(screen);

        for (self.visible_pr_elements.items) |numbers| {
            self.allocator.free(numbers);
        }
        self.visible_pr_elements.deinit(self.allocator);

        for (self.prs.items) |*pr| {
            pr.deinit(self.allocator);
        }
        self.prs.deinit(self.allocator);

        self.allocator.destroy(self.github_client);
        self.allocator.destroy(self);
    }

    pub fn navigateInto(screen: *Screen) !*Screen {
        const self = fromBase(screen);

        if (self.prs.items.len > 0) {
            const pr_details_screen = try PRDetailsScreen.create(self.allocator, self.prs.items[self.selected_index].number);
            return pr_details_screen;
        }
        return &self.base;
    }

    fn handleInput(screen: *Screen, key: vaxis.Key) !void {
        const self = fromBase(screen);

        if (self.loading) return;

        switch (key.codepoint) {
            'j' => {
                if (self.selected_index < self.prs.items.len - 1) {
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
                try self.loadPRs();
            },
            else => {},
        }
    }

    fn update(screen: *Screen) !void {
        const self = fromBase(screen);

        if (self.loading) {
            try self.loadPRs();
        }
    }

    fn loadPRs(self: *@This()) !void {
        defer self.loading = false;

        // Clear existing PRs
        for (self.prs.items) |*pr| {
            pr.deinit(self.allocator);
        }
        self.prs.clearRetainingCapacity();

        // Fetch new PRs
        const fetched_prs = self.github_client.fetchPRs() catch |err| {
            self.err_msg = switch (err) {
                error.GhCommandFailed => "GitHub CLI command failed. Make sure 'gh' is installed and authenticated.",
                error.MissingField => "Invalid response from GitHub API.",
                else => "Unknown error fetching PRs.",
            };
            return;
        };

        // Transfer ownership
        self.prs.deinit(self.allocator);
        self.prs = fetched_prs;
        self.selected_index = 0;
        self.offset = 0;
    }

    fn render(screen: *Screen, window: vaxis.Window) !void {
        const self = fromBase(screen);

        // Clear screen
        window.clear();
        const w = window.width;
        const h = window.height;

        // --- Header ---
        var header = window.child(layout.rect(
            0,
            0,
            w,
            3,
        ));

        // --- Body ---
        var body = window.child(layout.rect(
            0,
            3,
            w,
            h - 3,
        ));

        // =====================
        // Header
        // =====================
        _ = header.print(&.{
            .{
                .text = "GitHub PR Visualizer",
            },
        }, .{});

        // =====================
        // Loading state
        // =====================
        if (self.loading) {
            _ = body.print(&.{
                .{ .text = "Loading PRs..." },
            }, .{});
            return;
        }

        // =====================
        // Error state
        // =====================
        if (self.err_msg) |err| {
            _ = body.print(&.{
                .{ .text = "Error: " },
                .{ .text = err },
            }, .{});
            return;
        }

        // =====================
        // PR List
        // =====================
        if (self.prs.items.len == 0) {
            _ = body.print(&.{
                .{ .text = "No pull requests found." },
            }, .{});
            return;
        }

        // logic for multi lines list items
        const block_height: usize = 1;
        const visible_slots = @max(@as(usize, 1), body.height / block_height);

        if (self.selected_index < self.offset) {
            self.offset = self.selected_index;
        } else if (self.selected_index >= self.offset + visible_slots) {
            self.offset = self.selected_index - visible_slots + 1;
        }

        const visible = @min(self.prs.items.len -| self.offset, visible_slots);

        // Clear prev pr visible numbers
        for (self.visible_pr_elements.items) |numbr| {
            self.allocator.free(numbr);
        }
        self.visible_pr_elements.clearRetainingCapacity();

        // Build segments array
        var segments = std.ArrayList(vaxis.Segment){};
        defer segments.deinit(self.allocator);

        for (0..visible) |i| {
            const idx = self.offset + i;
            const pr = self.prs.items[idx];
            const is_selected = idx == self.selected_index;

            const base_style = if (is_selected) theme.selected_row_style else theme.normal_style;
            const muted_style = if (is_selected) theme.selected_row_style else theme.muted_style;
            const status_style = if (is_selected) theme.selected_row_style else pr_presentation.statusStyle(pr);

            const number_text = try std.fmt.allocPrint(self.allocator, "#{d}", .{pr.number});
            try self.visible_pr_elements.append(self.allocator, number_text);

            const meta_text = try std.fmt.allocPrint(self.allocator, "@{s}", .{pr.author});
            try self.visible_pr_elements.append(self.allocator, meta_text);

            const status_badge = try pr_presentation.allocStatusBadge(self.allocator, pr);
            try self.visible_pr_elements.append(self.allocator, status_badge);

            const lifecycle_badge = try self.allocator.dupe(u8, pr_presentation.lifecycleText(pr));
            try self.visible_pr_elements.append(self.allocator, lifecycle_badge);

            const review_text = try self.allocator.dupe(u8, pr_presentation.reviewText(pr));
            try self.visible_pr_elements.append(self.allocator, review_text);

            try segments.append(self.allocator, vaxis.Segment{
                .text = number_text,
                .style = if (is_selected) theme.selected_row_style else theme.pr_number_style,
            });

            try segments.append(self.allocator, vaxis.Segment{
                .text = " ",
                .style = base_style,
            });

            try segments.append(self.allocator, vaxis.Segment{
                .text = status_badge,
                .style = status_style,
            });

            try segments.append(self.allocator, vaxis.Segment{
                .text = " ",
                .style = base_style,
            });

            try segments.append(self.allocator, vaxis.Segment{
                .text = pr.title,
                .style = if (is_selected) base_style else theme.pr_title_style,
            });

            try segments.append(self.allocator, vaxis.Segment{
                .text = " ",
                .style = base_style,
            });

            try segments.append(self.allocator, vaxis.Segment{
                .text = meta_text,
                .style = if (is_selected) base_style else theme.pr_author_style,
            });

            try segments.append(self.allocator, vaxis.Segment{
                .text = " ",
                .style = base_style,
            });

            try segments.append(self.allocator, vaxis.Segment{
                .text = lifecycle_badge,
                .style = if (is_selected) theme.selected_row_style else pr_presentation.lifecycleStyle(pr),
            });

            try segments.append(self.allocator, vaxis.Segment{
                .text = " ",
                .style = base_style,
            });

            try segments.append(self.allocator, vaxis.Segment{
                .text = review_text,
                .style = muted_style,
            });

            if (i < visible - 1) {
                try segments.append(self.allocator, vaxis.Segment{
                    .text = "\n",
                    .style = base_style,
                });
            }
        }
        _ = body.print(segments.items, .{});
    }

    fn renderHelp(screen: *Screen, window: vaxis.Window) !void {
        _ = screen;
        try help_modal.render(window, "Pull Request List", &.{
            .{ .key = "j", .description = "Move selection down" },
            .{ .key = "k", .description = "Move selection up" },
            .{ .key = "enter", .description = "Open the selected pull request" },
            .{ .key = "r", .description = "Refresh the pull request list" },
            .{ .key = "q", .description = "Go back or quit from the top-level list" },
            .{ .key = "ctrl-q", .description = "Quit ghretty" },
            .{ .key = "?", .description = "Close this help modal" },
        });
    }

    fn fromBase(screen: *Screen) *@This() {
        return @fieldParentPtr("base", screen);
    }

    const vtable = Screen.VTable{
        .navigateInto = navigateInto,
        .handleInput = handleInput,
        .update = update,
        .render = render,
        .renderHelp = renderHelp,
        .deinit = deinit,
    };
};
