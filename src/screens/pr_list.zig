const std = @import("std");
const vaxis = @import("vaxis");
const Screen = @import("screen.zig").Screen;
const PR = @import("../models/pr.zig").PR;
const GitHubClient = @import("../github/client.zig").GitHubClient;

pub const PRListScreen = struct {
    base: Screen,
    allocator: std.mem.Allocator,
    github_client: *GitHubClient,
    prs: std.ArrayList(PR),
    selected_index: usize = 0,
    offset: usize = 0,
    loading: bool = true,
    err_msg: ?[]const u8 = null,
    
    pub fn create(allocator: std.mem.Allocator) !*Screen {
        const self = try allocator.create(@This());

        const github_client = try allocator.create(GitHubClient);

        github_client.* = GitHubClient.init(allocator);
        defer allocator.destroy(github_client);

        const prs = std.ArrayList(PR){};//.init(allocator);

        self.* = .{
            .base = .{ .vtable = &vtable },
            .allocator = allocator,
            .github_client = github_client,
            .prs = prs,
            .selected_index = 0,
            .offset = 0,
            .loading = true,
            .err_msg = null,
        };

        return &self.base;
    }

    fn deinit(screen: *Screen) void {
        const self = fromBase(screen);

        for (self.prs.items) |*pr| {
            pr.deinit(self.allocator);
        }
        self.prs.deinit(self.allocator);
        self.allocator.destroy(self.github_client);
        self.allocator.destroy(self);
    }

    fn handleInput(screen: *Screen, key: vaxis.Key) !void {
        const self = fromBase(screen);

        std.debug.print("debug(pr_list): handleInput\r\n", .{});
        if (self.loading) return;

        switch(key.codepoint){
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
            else => {
                if(key.matches(vaxis.Key.enter, .{})) {
                    if (self.prs.items.len > 0) {
                        std.debug.print("Opening PR #{}\n", .{self.prs.items[self.selected_index].number});
                    }
                }
            },
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

        _ = @import("../tui/theme.zig");
        
        // Clear screen
        window.clear();
        
        // Draw header
        var header = window.child(.{
            .direction = .horizontal,
            .height = 3,
        });
        
        try header.setCursor(.{ .row = 0, .col = 0 });
        try header.print("GitHub PR Visualizer", .{});
        
        try header.setCursor(.{ .row = 1, .col = 0 });
        try header.print("Press 'r' to refresh, 'q' to quit", .{});
        
        if (self.loading) {
            var loading_window = window.child(.{
                .direction = .vertical,
                .margin = .{ .top = 3 },
            });
            try loading_window.setCursor(.{ .row = 0, .col = 0 });
            try loading_window.print("Loading PRs...", .{});
            return;
        }
        
        if (self.err_msg) |err| {
            var error_window = window.child(.{
                .direction = .vertical,
                .margin = .{ .top = 3 },
            });
            try error_window.setCursor(.{ .row = 0, .col = 0 });
            try error_window.print("Error: {s}", .{err});
            try error_window.setCursor(.{ .row = 1, .col = 0 });
            try error_window.print("Press 'r' to retry", .{});
            return;
        }
        
        // Draw PR list
        var list_window = window.child(.{
            .direction = .vertical,
            .margin = .{ .top = 3 },
        });
        
        if (self.prs.items.len == 0) {
            try list_window.setCursor(.{ .row = 0, .col = 0 });
            try list_window.print("No pull requests found.", .{});
            return;
        }
        
        const visible_height = @min(self.prs.items.len - self.offset, list_window.rows());
        
        for (0..visible_height) |i| {
            const pr_index = self.offset + i;
            const pr = self.prs.items[pr_index];
            
            var row = list_window.child(.{
                .direction = .horizontal,
                .height = 1,
                .margin = .{ .top = @as(u16, @intCast(i)) },
            });
            
            // Highlight selected row
            if (pr_index == self.selected_index) {
                row.setStyle(.{
                    .fg = vaxis.Color.ansi(.black),
                    .bg = vaxis.Color.ansi(.white),
                    .bold = true,
                });
            }
            
            // PR number
            try row.setCursor(.{ .row = 0, .col = 0 });
            try row.print("#{}", .{pr.number});
            
            // Status indicators
            try row.setCursor(.{ .row = 0, .col = 8 });
            if (pr.is_draft) {
                try row.print("[DRAFT]", .{});
            }
            if (pr.review_requested) {
                try row.print("[REVIEW]", .{});
            }
            
            // Title
            try row.setCursor(.{ .row = 0, .col = 20 });
            const max_title_width = 40;
            if (pr.title.len > max_title_width) {
                try row.print("{s}...", .{pr.title[0..max_title_width]});
            } else {
                try row.print("{s}", .{pr.title});
            }
            
            // Author
            try row.setCursor(.{ .row = 0, .col = 65 });
            try row.print("@{s}", .{pr.author});
        }
        
        // Draw footer
        var footer = window.child(.{
            .direction = .horizontal,
            .margin = .{ .top = list_window.rows() + 3 },
            .height = 1,
        });
        
        try footer.setCursor(.{ .row = 0, .col = 0 });
        try footer.print("j/k: navigate • Enter: open • r: refresh • q: quit", .{});
    }

    fn fromBase(screen: *Screen) *@This() {
        return @fieldParentPtr("base", screen);
    }

    const vtable = Screen.VTable{
        .handleInput = handleInput,
        .update = update,
        .render = render,
        .deinit = deinit,
    };
};
