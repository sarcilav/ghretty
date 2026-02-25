const std = @import("std");
const vaxis = @import("vaxis");
const Screen = @import("screen.zig").Screen;
const PR = @import("../models/pr.zig").PR;
const GitHubClient = @import("../github/client.zig").GitHubClient;
const layout = @import("../tui/layout.zig");

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
            .selected_index = 0,
            .offset = 0,
            .loading = true,
            .err_msg = null,
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

    fn handleInput(screen: *Screen, key: vaxis.Key) !void {
        const self = fromBase(screen);

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
        const w = window.width;
        const h = window.height;

        // --- Header ---
        var header = window.child(layout.rect(
            0,
            0,
            w,
            3,
        ));

        // --- Footer ---
        var footer = window.child(layout.rect(
            h - 1,
            0,
            w,
            1,
        ));

        // --- Body ---
        var body = window.child(layout.rect(
            0,
            3,
            w,
            h - 4,
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

        for (0..visible) |i| {
            const idx = self.offset + i;
            const pr = self.prs.items[idx];

            //const selected = idx == self.selected_index;
            const line = try std.fmt.allocPrint(
                self.allocator,
                "#{d} {s} @{s}",
                .{ pr.number, pr.title, pr.author },
            );
            const valid = std.unicode.utf8ValidateSlice(line);
            std.debug.assert(valid);

            try self.lines.append(self.allocator, line);

            _ = body.print(&.{
                .{ .text = line },
                }, .{});
        }

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
        .handleInput = handleInput,
        .update = update,
        .render = render,
        .deinit = deinit,
    };
};
