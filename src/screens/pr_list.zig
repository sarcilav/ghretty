const std = @import("std");
const vaxis = @import("vaxis");
const Screen = @import("screen.zig").Screen;
const PRDetailsScreen = @import("pr_details.zig").PRDetailsScreen;
const PR = @import("../models/pr.zig").PR;
const GitHubClient = @import("../github/client.zig").GitHubClient;
const layout = @import("../tui/layout.zig");
const theme = @import("../tui/theme.zig");

pub const PRListScreen = struct {
    base: Screen,
    allocator: std.mem.Allocator,
    github_client: *GitHubClient,
    prs: std.ArrayList(PR),
    selected_index: usize = 0,
    offset: usize = 0,
    loading: bool = true,
    err_msg: ?[]const u8 = null,
    lines: std.ArrayListUnmanaged([]u8),

    pub fn create(allocator: std.mem.Allocator) !*Screen {
        const self = try allocator.create(@This());

        const github_client = try allocator.create(GitHubClient);

        const lines = std.ArrayListUnmanaged([]u8){};
        github_client.* = GitHubClient.init(allocator);

        const prs = std.ArrayList(PR){};

        self.* = .{
            .base = .{ .vtable = &vtable },
            .allocator = allocator,
            .github_client = github_client,
            .prs = prs,
            .lines = lines,
        };

        return &self.base;
    }

    fn deinit(screen: *Screen) void {
        const self = fromBase(screen);

        for (self.prs.items) |*pr| {
            pr.deinit(self.allocator);
        }

        for (self.lines.items) |line| {
            self.allocator.free(line);
        }
        self.lines.deinit(self.allocator);

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
            4,
        ));

        // --- Body ---
        var body = window.child(layout.rect(
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

        // =====================
        // Header
        // =====================
        _ = header.print(&.{
            .{
                .text = "GitHub PR Visualizer",
            },
        }, .{});

        _ = header.print(&.{
            .{
                .text = "\nPress r: refresh  ctrl-q: quit",
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

        const visible = @min(
            self.prs.items.len -| self.offset,
            body.height,
        );

        // Clear existing lines
        for (self.lines.items) |line| {
            self.allocator.free(line);
        }
        self.lines.clearRetainingCapacity();

        // Build segments array
        var segments = std.ArrayList(vaxis.Segment){};
        defer segments.deinit(self.allocator);

        for (0..visible) |i| {
            const idx = self.offset + i;
            const pr = self.prs.items[idx];
            const is_selected = idx == self.selected_index;

            // Create line text
            const line = try std.fmt.allocPrint(
                self.allocator,
                "#{d} {s} @{s}",
                .{ pr.number, pr.title, pr.author },
            );

            // Store for navigation
            try self.lines.append(self.allocator, line);

            // Create segment with appropriate style
            const segment = vaxis.Segment{
                .text = line,
                .style = if (is_selected) theme.selected_row_style else theme.normal_style,
            };

            try segments.append(self.allocator, segment);

            // Add newline segment (except after last line)
            if (i < visible - 1) {
                try segments.append(self.allocator, .{ .text = "\n", .style = theme.normal_style });
            }
        }

        // Print all segments at once
        _ = body.print(segments.items, .{});

        // =====================
        // Footer
        // =====================
        _ = footer.print(&.{
            .{ .text = "j/k: navigate • Enter: open • r: refresh" },
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
