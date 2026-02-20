const std = @import("std");
const vaxis = @import("vaxis");

// TODO: Implement reusable UI components
// - List component with virtualization
// - Scrollable view
// - Status bar
// - Loading indicator

pub const List = struct {
    items: []const []const u8,
    selected_index: usize = 0,
    scroll_offset: usize = 0,

    pub fn render(self: *@This(), window: vaxis.Window) !void {
        const visible_height = window.rows();
        const start_idx = self.scroll_offset;
        const end_idx = @min(start_idx + visible_height, self.items.len);

        for (start_idx..end_idx, 0..) |idx, row| {
            const is_selected = idx == self.selected_index;
            var item_window = window.child(.{
                .direction = .horizontal,
                .height = 1,
                .margin = .{ .top = @as(u16, @intCast(row)) },
            });

            if (is_selected) {
                item_window.setStyle(.{
                    .fg = vaxis.Color.ansi(.black),
                    .bg = vaxis.Color.ansi(.white),
                });
            }

            try item_window.setCursor(.{ .row = 0, .col = 0 });
            try item_window.print("{s}", .{self.items[idx]});
        }
    }
};
