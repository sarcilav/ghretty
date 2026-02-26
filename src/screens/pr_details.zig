const std = @import("std");
const vaxis = @import("vaxis");
const Screen = @import("screen.zig").Screen;
const PR = @import("../models/pr.zig").PR;
const GitHubClient = @import("../github/client.zig").GitHubClient;
const layout = @import("../tui/layout.zig");

pub const PRDetailsScreen = struct {
    base: Screen,
    allocator: std.mem.Allocator,
    github_client: *GitHubClient,
    pr: PR,
    scroll_offset: usize = 0,
    loading: bool = true,
    err_msg: ?[]const u8 = null,

    pub fn create(allocator: std.mem.Allocator, pr: PR) !*Screen {
        const self = try allocator.create(@This());

        const github_client = try allocator.create(GitHubClient);
        github_client.* = GitHubClient.init(allocator);

        self.* = .{
            .base = .{ .vtable = &vtable },
            .allocator = allocator,
            .github_client = github_client,
            .pr = pr,
            .loading = true,
            .err_msg = null,
        };
        return &self.base;
    }

    pub fn deinit(screen: *Screen) void {
        const self = fromBase(screen);

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
            // if (key.matches(vaxis.Key.tty_key, .{ .codepoint = 'q' })) {
            // TODO: Navigate back to PR list
            'j' => {
                self.scroll_offset += 1;
            },
            'k' => {
                if (self.scroll_offset > 0) {
                    self.scroll_offset -= 1;
                }
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
        const fetched_pr = self.github_client.fetchPRDetails(self.pr.number) catch |err| {
            self.err_msg = switch (err) {
                error.GhCommandFailed => "GitHub CLI command failed. Make sure 'gh' is installed and authenticated.",
                error.MissingField => "Invalid response from GitHub API.",
                else => "Unknown error fetching PRs.",
            };
            return;
        };
        self.pr = fetched_pr;
        self.scroll_offset = 0;
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
            3,
        ));

        // --- Body ---
        var content = window.child(layout.rect(
            0,
            3,
            w,
            h - 4,
        ));

        // --- Footer ---
        var footer = window.child(layout.rect(
            h - 1,
            0,
            w,
            1,
        ));

        _ = header.print(&.{
            .{
                .text = "PR #{}: {s}", // .{ self.pr.number, self.pr.title });
            },
        }, .{});
        _ = header.print(&.{
            .{
                .text = "\nAuthor: @{s}", // .{self.pr.author});
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
        // TODO: Draw PR description and file changes
        _ = content.print(&.{
            .{ .text = "PR Details Screen - TODO: Implement" },
        }, .{});

        // =====================
        // Footer
        // =====================
        _ = footer.print(&.{
            .{ .text = "j/k: navigate • Enter: open • r: refresh • q: quit" },
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
