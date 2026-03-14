const std = @import("std");
const vaxis = @import("vaxis");
const Screen = @import("screen.zig").Screen;
const PR = @import("../models/pr.zig").PR;
const git = @import("../models/git.zig");
const GitHubClient = @import("../github/client.zig").GitHubClient;
const layout = @import("../tui/layout.zig");
const pr_presentation = @import("../tui/pr_presentation.zig");
const theme = @import("../tui/theme.zig");
const Section = @import("../tui/section.zig").Section;
const HelpEntry = @import("../tui/section.zig").HelpEntry;
const FileDiffSection = @import("../tui/file_diff_section.zig").FileDiffSection;
const PRDescriptionSection = @import("../tui/pr_description_section.zig").PRDescriptionSection;
const help_modal = @import("../tui/help_modal.zig");
const review_modal = @import("../tui/review_modal.zig");
const merge_modal = @import("../tui/merge_modal.zig");
const PRReviewAction = @import("../models/pr.zig").PRReviewAction;
const PRMergeAction = @import("../models/pr.zig").PRMergeAction;
const TextInput = vaxis.widgets.TextInput;

pub const PRDetailsScreen = struct {
    const ActiveModal = enum {
        none,
        review,
        merge,
    };

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
    pr_status_badge: ?[]const u8 = null,
    pr_lifecycle_badge: ?[]const u8 = null,
    pr_review_text: ?[]const u8 = null,
    pr_file_count_text: ?[]const u8 = null,
    pr_additions_text: ?[]const u8 = null,
    pr_deletions_text: ?[]const u8 = null,
    current_section_type: enum { description, diff } = .description,
    active_modal: ActiveModal = .none,
    review_action: PRReviewAction = .approve,
    merge_action: PRMergeAction = .merge_commit,
    modal_input: TextInput,
    modal_error: ?[]const u8 = null,
    flash_message: ?[]const u8 = null,
    flash_message_is_error: bool = false,

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
            .modal_input = TextInput.init(allocator),
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
        if (self.pr_status_badge) |badge| self.allocator.free(badge);
        if (self.pr_lifecycle_badge) |badge| self.allocator.free(badge);
        if (self.pr_review_text) |text| self.allocator.free(text);
        if (self.pr_file_count_text) |text| self.allocator.free(text);
        if (self.pr_additions_text) |text| self.allocator.free(text);
        if (self.pr_deletions_text) |text| self.allocator.free(text);
        if (self.flash_message) |message| self.allocator.free(message);
        if (self.modal_error) |message| self.allocator.free(message);
        self.modal_input.deinit();
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

        if (self.active_modal != .none) {
            try self.handleModalInput(key);
            return;
        }

        // Hotkeys to switch sections
        switch (key.codepoint) {
            'v' => {
                self.openReviewModal();
                return;
            },
            'm' => {
                try self.openMergeModal();
                return;
            },
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
        if (self.pr_status_badge) |badge| {
            self.allocator.free(badge);
            self.pr_status_badge = null;
        }
        if (self.pr_lifecycle_badge) |badge| {
            self.allocator.free(badge);
            self.pr_lifecycle_badge = null;
        }
        if (self.pr_review_text) |text| {
            self.allocator.free(text);
            self.pr_review_text = null;
        }
        if (self.pr_file_count_text) |text| {
            self.allocator.free(text);
            self.pr_file_count_text = null;
        }
        if (self.pr_additions_text) |text| {
            self.allocator.free(text);
            self.pr_additions_text = null;
        }
        if (self.pr_deletions_text) |text| {
            self.allocator.free(text);
            self.pr_deletions_text = null;
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
        self.pr_author = try std.fmt.allocPrint(self.allocator, "@{s}", .{self.pr.?.author});
        self.pr_status_badge = try pr_presentation.allocStatusBadge(self.allocator, self.pr.?);
        self.pr_lifecycle_badge = try self.allocator.dupe(u8, pr_presentation.lifecycleText(self.pr.?));
        self.pr_review_text = try self.allocator.dupe(u8, pr_presentation.reviewText(self.pr.?));
        if (self.pr.?.files) |files| {
            var additions: u32 = 0;
            var deletions: u32 = 0;
            for (files.items) |file| {
                additions += file.additions;
                deletions += file.deletions;
            }
            self.pr_file_count_text = try std.fmt.allocPrint(self.allocator, "{} files  •  ", .{files.items.len});
            self.pr_additions_text = try std.fmt.allocPrint(self.allocator, "+{}", .{additions});
            self.pr_deletions_text = try std.fmt.allocPrint(self.allocator, "-{}", .{deletions});
        }

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
        var header = window.child(layout.rect(0, 0, w, 5));

        // --- Tabs ---
        var tabs_area = window.child(layout.rect(0, 5, w, 3));

        // --- Content ---
        var content = window.child(layout.rect(0, 8, w, h - 8));

        // Render header in one print call so later lines do not overwrite the title.
        var header_segments = std.ArrayList(vaxis.Segment){};
        defer header_segments.deinit(self.allocator);

        if (self.pr_title) |title| {
            try header_segments.append(self.allocator, .{
                .text = title,
                .style = theme.header_style,
            });
        }
        if (self.pr) |pr| {
            if (header_segments.items.len > 0) {
                try header_segments.append(self.allocator, .{
                    .text = "\n",
                    .style = theme.normal_style,
                });
            }
            try header_segments.append(self.allocator, .{
                .text = self.pr_author orelse "",
                .style = theme.pr_author_style,
            });
            try header_segments.append(self.allocator, .{
                .text = " ",
                .style = theme.normal_style,
            });
            try header_segments.append(self.allocator, .{
                .text = self.pr_status_badge orelse pr_presentation.statusText(pr),
                .style = pr_presentation.statusStyle(pr),
            });
            try header_segments.append(self.allocator, .{
                .text = " ",
                .style = theme.normal_style,
            });
            try header_segments.append(self.allocator, .{
                .text = self.pr_lifecycle_badge orelse pr_presentation.lifecycleText(pr),
                .style = pr_presentation.lifecycleStyle(pr),
            });
            try header_segments.append(self.allocator, .{
                .text = " ",
                .style = theme.normal_style,
            });
            try header_segments.append(self.allocator, .{
                .text = self.pr_review_text orelse pr_presentation.reviewText(pr),
                .style = theme.muted_style,
            });

            if (self.pr_file_count_text) |count_text| {
                try header_segments.append(self.allocator, .{
                    .text = "\n",
                    .style = theme.normal_style,
                });
                try header_segments.append(self.allocator, .{
                    .text = count_text,
                    .style = theme.muted_style,
                });
                if (self.pr_additions_text) |additions_text| {
                    try header_segments.append(self.allocator, .{
                        .text = additions_text,
                        .style = theme.success_style,
                    });
                }
                try header_segments.append(self.allocator, .{
                    .text = "  ",
                    .style = theme.normal_style,
                });
                if (self.pr_deletions_text) |deletions_text| {
                    try header_segments.append(self.allocator, .{
                        .text = deletions_text,
                        .style = theme.danger_style,
                    });
                }
            }

            if (self.flash_message) |message| {
                try header_segments.append(self.allocator, .{
                    .text = "\n",
                    .style = theme.normal_style,
                });
                try header_segments.append(self.allocator, .{
                    .text = message,
                    .style = if (self.flash_message_is_error) theme.error_style else theme.success_style,
                });
            }
        }

        if (header_segments.items.len > 0) {
            _ = header.print(header_segments.items, .{});
        }

        // Render tabs
        const desc_active = self.current_section_type == .description;
        const diff_active = self.current_section_type == .diff;

        const desc_tab = "Description";
        const diff_tab = "Files";

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

        switch (self.active_modal) {
            .review => try review_modal.render(window, &self.modal_input, self.review_action, self.modal_error),
            .merge => try merge_modal.render(window, &self.modal_input, self.merge_action, self.modal_error),
            .none => {},
        }
    }

    fn renderHelp(screen: *Screen, window: vaxis.Window) !void {
        const self = fromBase(screen);
        var section_title: ?[]const u8 = null;

        var entries = std.ArrayList(HelpEntry){};
        defer entries.deinit(self.allocator);

        try entries.appendSlice(self.allocator, &.{
            .{ .key = "d", .description = "Switch to the description view" },
            .{ .key = "f", .description = "Switch to the files view" },
            .{ .key = "v", .description = "Open the PR review modal" },
            .{ .key = "m", .description = "Open the PR merge/close modal" },
            .{ .key = "r", .description = "Refresh pull request details" },
        });

        if (self.current_section) |section| {
            const section_help = section.helpContent();
            section_title = section_help.title;
            try entries.appendSlice(self.allocator, section_help.entries);
        }

        try entries.appendSlice(self.allocator, &.{
            .{ .key = "q", .description = "Go back" },
            .{ .key = "ctrl-q", .description = "Quit ghretty" },
            .{ .key = "?", .description = "Close this help modal" },
        });

        const title = section_title orelse switch (self.current_section_type) {
            .description => "Pull Request Details: Description",
            .diff => "Pull Request Details: Files",
        };

        try help_modal.render(window, title, entries.items);
    }

    fn fromBase(screen: *Screen) *@This() {
        return @fieldParentPtr("base", screen);
    }

    fn openReviewModal(self: *@This()) void {
        self.active_modal = .review;
        self.review_action = .approve;
        self.clearModalError();
        self.modal_input.clearRetainingCapacity();
    }

    fn openMergeModal(self: *@This()) !void {
        const pr = self.pr orelse {
            try self.setFlashMessage("Pull request details are still loading.", true);
            return;
        };

        if (pr.state != .open) {
            try self.setFlashMessage("Only open pull requests can be merged or closed.", true);
            return;
        }

        self.active_modal = .merge;
        self.merge_action = .merge_commit;
        self.clearModalError();
        self.modal_input.clearRetainingCapacity();
    }

    fn closeModal(self: *@This()) void {
        self.active_modal = .none;
        self.clearModalError();
        self.modal_input.clearRetainingCapacity();
    }

    fn handleModalInput(self: *@This(), key: vaxis.Key) !void {
        if (key.matches(vaxis.Key.escape, .{}) or key.matches('q', .{})) {
            self.closeModal();
            return;
        }

        if (key.matches(vaxis.Key.tab, .{})) {
            switch (self.active_modal) {
                .review => self.review_action = nextReviewAction(self.review_action),
                .merge => self.merge_action = nextMergeAction(self.merge_action),
                .none => {},
            }
            self.clearModalError();
            return;
        }

        if (key.matches(vaxis.Key.tab, .{ .shift = true })) {
            switch (self.active_modal) {
                .review => self.review_action = previousReviewAction(self.review_action),
                .merge => self.merge_action = previousMergeAction(self.merge_action),
                .none => {},
            }
            self.clearModalError();
            return;
        }

        if (key.matches(vaxis.Key.enter, .{ .shift = true })) {
            switch (self.active_modal) {
                .review => try self.submitReviewAction(),
                .merge => try self.submitMergeAction(),
                .none => {},
            }
            return;
        }

        try self.modal_input.update(.{ .key_press = key });
        self.clearModalError();
    }

    fn submitReviewAction(self: *@This()) !void {
        const body = try self.allocReviewInputText();
        defer if (body) |text| self.allocator.free(text);

        if (self.review_action == .comment and (body == null or body.?.len == 0)) {
            try self.setModalError("A comment is required for comment reviews.");
            return;
        }

        self.github_client.submitPRReview(self.pr_number, self.review_action, body) catch |err| {
            const message = switch (err) {
                error.MissingReviewBody => "A comment is required for this action.",
                error.GhCommandFailed => "GitHub CLI command failed while submitting the PR action.",
                else => "Unable to submit the PR action.",
            };
            try self.setModalError(message);
            return;
        };

        self.closeModal();
        try self.setFlashMessage(successMessage(self.review_action), false);
        self.loading = true;
    }

    fn submitMergeAction(self: *@This()) !void {
        const message = try self.allocTextInputText(&self.modal_input);
        defer if (message) |text| self.allocator.free(text);

        self.github_client.submitPRMergeAction(self.pr_number, self.merge_action, message) catch |err| {
            const merge_message = switch (err) {
                error.GhCommandFailed => "GitHub CLI command failed while applying the PR action.",
                else => "Unable to apply the PR action.",
            };
            try self.setModalError(merge_message);
            return;
        };

        self.closeModal();
        try self.setFlashMessage(mergeSuccessMessage(self.merge_action), false);
        self.loading = true;
    }

    fn allocReviewInputText(self: *@This()) !?[]const u8 {
        return self.allocTextInputText(&self.modal_input);
    }

    fn allocTextInputText(self: *@This(), input: *TextInput) !?[]const u8 {
        const first_half = input.buf.firstHalf();
        const second_half = input.buf.secondHalf();
        const len = first_half.len + second_half.len;
        if (len == 0) return null;

        const buf = try self.allocator.alloc(u8, len);
        @memcpy(buf[0..first_half.len], first_half);
        @memcpy(buf[first_half.len..], second_half);
        return buf;
    }

    fn setFlashMessage(self: *@This(), message: []const u8, is_error: bool) !void {
        if (self.flash_message) |current| self.allocator.free(current);
        self.flash_message = try self.allocator.dupe(u8, message);
        self.flash_message_is_error = is_error;
    }

    fn setModalError(self: *@This(), message: []const u8) !void {
        if (self.modal_error) |current| self.allocator.free(current);
        self.modal_error = try self.allocator.dupe(u8, message);
    }

    fn clearModalError(self: *@This()) void {
        if (self.modal_error) |current| {
            self.allocator.free(current);
            self.modal_error = null;
        }
    }

    fn nextReviewAction(action: PRReviewAction) PRReviewAction {
        return switch (action) {
            .approve => .request_changes,
            .request_changes => .comment,
            .comment => .approve,
        };
    }

    fn previousReviewAction(action: PRReviewAction) PRReviewAction {
        return switch (action) {
            .approve => .comment,
            .request_changes => .approve,
            .comment => .request_changes,
        };
    }

    fn nextMergeAction(action: PRMergeAction) PRMergeAction {
        return switch (action) {
            .merge_commit => .squash,
            .squash => .rebase,
            .rebase => .close,
            .close => .merge_commit,
        };
    }

    fn previousMergeAction(action: PRMergeAction) PRMergeAction {
        return switch (action) {
            .merge_commit => .close,
            .squash => .merge_commit,
            .rebase => .squash,
            .close => .rebase,
        };
    }

    fn successMessage(action: PRReviewAction) []const u8 {
        return switch (action) {
            .approve => "Approval submitted.",
            .request_changes => "Change request submitted.",
            .comment => "Comment submitted.",
        };
    }

    fn mergeSuccessMessage(action: PRMergeAction) []const u8 {
        return switch (action) {
            .merge_commit => "Pull request merged with a merge commit.",
            .squash => "Pull request squashed and merged.",
            .rebase => "Pull request rebased and merged.",
            .close => "Pull request closed.",
        };
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
