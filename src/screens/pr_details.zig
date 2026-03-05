const std = @import("std");
const vaxis = @import("vaxis");
const Screen = @import("screen.zig").Screen;
const PR = @import("../models/pr.zig").PR;
const git = @import("../models/git.zig");
const GitHubClient = @import("../github/client.zig").GitHubClient;
const layout = @import("../tui/layout.zig");
const theme = @import("../tui/theme.zig");
const Section = @import("../tui/section.zig").Section;
const FileDiffSection = @import("../tui/file_diff_section.zig").FileDiffSection;

pub const PRDetailsScreen = struct {
    base: Screen,
    allocator: std.mem.Allocator,
    github_client: *GitHubClient,
    pr_number: u32 = 0,
    pr: ?PR = null,
    diff_section: ?*Section = null,
    loading: bool = true,
    err_msg: ?[]const u8 = null,
    file_diffs: std.ArrayList(git.FileDiff),
    pr_title: ?[]const u8 = null,
    pr_author: ?[]const u8 = null,

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
            .diff_section = null,
            .file_diffs = file_diffs,
        };
        return &self.base;
    }

    pub fn deinit(screen: *Screen) void {
        const self = fromBase(screen);

        // Clean up diff_section if it exists
        if (self.diff_section) |diff_section| {
            diff_section.deinit();
        }

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

        // Delegate to diff section for navigation keys
        if (self.diff_section) |diff_section| {
            switch (key.codepoint) {
                'j', 'k', '\t' => {
                    diff_section.handleInput(key);
                    return;
                },
                else => {},
            }
        }

        switch (key.codepoint) {
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

        // Update diff section if it exists
        if (self.diff_section) |diff_section| {
            try diff_section.update();
        }
    }

    fn loadPRDetails(self: *@This()) !void {
        defer self.loading = false;

        // Clean up existing diff_section
        if (self.diff_section) |diff_section| {
            diff_section.deinit();
            self.diff_section = null;
        }

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

        // Create diff section with the file diffs
        self.diff_section = try FileDiffSection.create(self.allocator, self.file_diffs);

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

        // =====================
        // Render diff section
        // =====================
        if (self.diff_section) |diff_section| {
            try diff_section.render(content);
        }

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
