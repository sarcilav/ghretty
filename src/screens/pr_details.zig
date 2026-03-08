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
const PRDescriptionSection = @import("../tui/pr_description_section.zig").PRDescriptionSection;

pub const PRDetailsScreen = struct {
    base: Screen,
    allocator: std.mem.Allocator,
    github_client: *GitHubClient,
    pr_number: u32 = 0,
    pr: ?PR = null,
    current_section: ?*Section = null,
    loading: bool = true,
    err_msg: ?[]const u8 = null,
    file_diffs: std.ArrayList(git.FileDiff),
    pr_title: ?[]const u8 = null,
    pr_author: ?[]const u8 = null,
    current_section_type: enum { description, diff } = .description,

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
            .current_section_type = .description,
        };
        return &self.base;
    }

    pub fn deinit(screen: *Screen) void {
        const self = fromBase(screen);

        // Clean up current_section if it exists
        if (self.current_section) |section| {
            section.deinit();
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

        // Hotkeys to switch sections
        switch (key.codepoint) {
            'd' => {
                // Switch to description section
                if (self.current_section_type != .description) {
                    self.current_section_type = .description;
                    // Recreate the section if PR is loaded
                    if (self.pr) |pr| {
                        if (self.current_section) |section| {
                            section.deinit();
                        }
                        if (pr.body) |body| {
                            self.current_section = try PRDescriptionSection.create(self.allocator, body);
                        } else {
                            self.current_section = null;
                        }
                    }
                }
                return;
            },
            'f' => {
                // Switch to diff section
                if (self.current_section_type != .diff) {
                    self.current_section_type = .diff;
                    // Recreate the section if PR is loaded
                    if (self.pr) |_| {
                        if (self.current_section) |section| {
                            section.deinit();
                        }
                        if (self.file_diffs.items.len > 0) {
                            self.current_section = try FileDiffSection.create(self.allocator, self.file_diffs);
                        } else {
                            self.current_section = null;
                        }
                    }
                }
                return;
            },
            else => {
                // Pass input to current section
                if (self.current_section) |section| {
                    section.handleInput(key);
                }
            },
        }

        // Refresh still works
        if (key.codepoint == 'r') {
            self.loading = true;
            self.err_msg = null;
            try self.loadPRDetails();
        }
    }

    fn update(screen: *Screen) !void {
        const self = fromBase(screen);

        if (self.loading) {
            try self.loadPRDetails();
        }

        // Update current section if it exists
        if (self.current_section) |section| {
            try section.update();
        }
    }

    fn loadPRDetails(self: *@This()) !void {
        defer self.loading = false;

        // Clean up existing section
        if (self.current_section) |section| {
            section.deinit();
            self.current_section = null;
        }

        // Clean up file_diffs
        for (self.file_diffs.items) |*file_diff| {
            file_diff.deinit(self.allocator);
        }
        self.file_diffs.deinit(self.allocator);

        if (self.pr_title) |title| {
            self.allocator.free(title);
            self.pr_title = null;
        }
        if (self.pr_author) |author| {
            self.allocator.free(author);
            self.pr_author = null;
        }
        if (self.pr) |*pr| {
            pr.deinit(self.allocator);
            self.pr = null;
        }

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

        // Create initial section based on current_section_type
        switch (self.current_section_type) {
            .description => {
                if (fetched_pr.body) |body| {
                    self.current_section = try PRDescriptionSection.create(self.allocator, body);
                }
            },
            .diff => {
                if (self.file_diffs.items.len > 0) {
                    self.current_section = try FileDiffSection.create(self.allocator, self.file_diffs);
                }
            },
        }
    }

    pub fn render(screen: *Screen, window: vaxis.Window) !void {
        const self = fromBase(screen);
        window.clear();

        const w = window.width;
        const h = window.height;

        // --- Header ---
        var header = window.child(layout.rect(0, 0, w, 4));

        // --- Tabs ---
        var tabs_area = window.child(layout.rect(0, 4, w, 3));

        // --- Content ---
        var content = window.child(layout.rect(0, 7, w, h - 11));

        // --- Footer ---
        var footer = window.child(layout.rect(0, h - 4, w, 4));

        // Render header
        if (self.pr_title) |title| {
            _ = header.print(&.{.{ .text = title }}, .{});
        }
        if (self.pr_author) |author| {
            _ = header.print(&.{.{ .text = author }}, .{});
        }

        // Render tabs
        const desc_active = self.current_section_type == .description;
        const diff_active = self.current_section_type == .diff;

        const desc_tab = if (desc_active) "[d] Description" else " d  Description";
        const diff_tab = if (diff_active) "[f] Files" else " f  Files";

        _ = tabs_area.print(&.{
            .{ .text = desc_tab, .style = if (desc_active) theme.selected_row_style else theme.normal_style },
            .{ .text = " | ", .style = theme.normal_style },
            .{ .text = diff_tab, .style = if (diff_active) theme.selected_row_style else theme.normal_style },
        }, .{});

        // Loading/error states
        if (self.loading) {
            _ = content.print(&.{.{ .text = "Loading PR..." }}, .{});
            return;
        }
        if (self.err_msg) |err| {
            _ = content.print(&.{
                .{ .text = "Error: " },
                .{ .text = err },
            }, .{});
            return;
        }

        // Render current section if it exists
        if (self.current_section) |section| {
            try section.render(content);
        } else {
            // No section available (e.g., no description for description section)
            switch (self.current_section_type) {
                .description => {
                    _ = content.print(&.{.{ .text = "No description provided" }}, .{});
                },
                .diff => {
                    _ = content.print(&.{.{ .text = "No files to display" }}, .{});
                },
            }
        }

        // Footer
        _ = footer.print(&.{
            .{ .text = "d: Description • f: Files • r: refresh • q: back • ctrl-q: quit" },
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
