const std = @import("std");
const vaxis = @import("vaxis");
const Screen = @import("screen.zig").Screen;
const PR = @import("ghretty").models.PR;

pub const PRDetailsScreen = struct {
    base: Screen,
    pr: PR,
    scroll_offset: usize = 0,

    pub fn init(allocator: std.mem.Allocator, pr: PR) !@This() {
        const screen = try Screen.init(allocator);
        return @This(){
            .base = screen,
            .pr = pr,
        };
    }

    pub fn deinit(self: *@This()) void {
        self.pr.deinit(self.base.allocator);
        self.base.deinit();
    }

    pub fn handleInput(self: *@This(), key: vaxis.Key) !void {
        if (key.matches(vaxis.Key.tty_key, .{ .codepoint = 'q' })) {
            // TODO: Navigate back to PR list
        } else if (key.matches(vaxis.Key.tty_key, .{ .codepoint = 'j' })) {
            self.scroll_offset += 1;
        } else if (key.matches(vaxis.Key.tty_key, .{ .codepoint = 'k' })) {
            if (self.scroll_offset > 0) {
                self.scroll_offset -= 1;
            }
        }
    }

    pub fn render(self: *@This(), window: vaxis.Window) !void {
        window.clear();
        
        // Draw header with PR info
        var header = window.child(.{
            .direction = .horizontal,
            .height = 3,
        });
        
        try header.setCursor(.{ .row = 0, .col = 0 });
        try header.print("PR #{}: {s}", .{ self.pr.number, self.pr.title });
        
        try header.setCursor(.{ .row = 1, .col = 0 });
        try header.print("Author: @{s}", .{self.pr.author});
        
        // TODO: Draw PR description and file changes
        var content = window.child(.{
            .direction = .vertical,
            .margin = .{ .top = 4 },
        });
        
        try content.setCursor(.{ .row = 0, .col = 0 });
        try content.print("PR Details Screen - TODO: Implement", .{});
        
        // Draw footer
        var footer = window.child(.{
            .direction = .horizontal,
            .margin = .{ .top = content.rows() + 4 },
            .height = 1,
        });
        
        try footer.setCursor(.{ .row = 0, .col = 0 });
        try footer.print("j/k: scroll • q: back", .{});
    }
};
