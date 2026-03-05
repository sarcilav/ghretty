const std = @import("std");
const vaxis = @import("vaxis");

pub const Collapsible = struct {
    title: []const u8,
    collapsed: bool = false,

    pub fn renderHeader(
        self: *const @This(),
        window: vaxis.Window,
        row: usize,
    ) !void {
        const indicator = if (self.collapsed) "[>] " else "[v] ";
        _ = window.printAt(0, @intCast(row), &.{
            .{ .text = indicator },
            .{ .text = self.title },
        }, .{});
    }

    pub fn toggle(self: *@This()) void {
        self.collapsed = !self.collapsed;
    }
};
