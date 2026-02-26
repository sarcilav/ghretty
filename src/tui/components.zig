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

        // Build text for all visible items
        var full_text = std.ArrayList(u8).init(window.allocator);
        defer full_text.deinit();

        for (start_idx..end_idx) |idx| {
            const is_selected = idx == self.selected_index;

            if (is_selected) {
                // Mark selected items with '>'
                try full_text.appendSlice("> ");
                try full_text.appendSlice(self.items[idx]);
            } else {
                try full_text.appendSlice("  ");
                try full_text.appendSlice(self.items[idx]);
            }

            // Add newline except after last item
            if (idx < end_idx - 1) {
                try full_text.append('\n');
            }
        }

        // Print all text at once
        _ = window.print(&.{
            .{ .text = full_text.items },
        }, .{});
    }
};
