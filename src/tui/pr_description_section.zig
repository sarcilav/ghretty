const std = @import("std");
const vaxis = @import("vaxis");
const Section = @import("section.zig").Section;
const HelpContent = @import("section.zig").HelpContent;
const theme = @import("theme.zig");

pub const PRDescriptionSection = struct {
    base: Section,
    allocator: std.mem.Allocator,
    description: []const u8,
    scroll_offset: usize = 0,

    pub fn create(allocator: std.mem.Allocator, description: []const u8) !*Section {
        const self = try allocator.create(@This());
        self.* = .{
            .base = .{ .vtable = &vtable, .data = self },
            .allocator = allocator,
            .description = description,
        };
        return &self.base;
    }

    fn handleInput(data: *anyopaque, key: vaxis.Key) void {
        const self: *@This() = @ptrCast(@alignCast(data));

        switch (key.codepoint) {
            'j' => {
                // Scroll down
                self.scroll_offset += 1;
            },
            'k' => {
                // Scroll up
                if (self.scroll_offset > 0) {
                    self.scroll_offset -= 1;
                }
            },
            else => {},
        }
    }

    fn update(data: *anyopaque) !void {
        _ = data;
    }

    fn render(data: *anyopaque, window: vaxis.Window) !void {
        const self: *@This() = @ptrCast(@alignCast(data));

        var segments = std.ArrayList(vaxis.Segment){};
        defer segments.deinit(self.allocator);

        var lines = std.mem.splitScalar(u8, self.description, '\n');
        var line_num: usize = 0;
        var visible_line: usize = 0;
        const visible_area = window.height;

        while (lines.next()) |line| : (line_num += 1) {
            if (line_num < self.scroll_offset) continue;
            if (visible_line >= visible_area) break;

            try segments.append(self.allocator, vaxis.Segment{
                .text = line,
                .style = theme.normal_style,
            });

            if (visible_line < visible_area - 1) {
                try segments.append(self.allocator, vaxis.Segment{
                    .text = "\n",
                    .style = theme.normal_style,
                });
            }

            visible_line += 1;
        }

        _ = window.print(segments.items, .{});
    }

    fn deinit(data: *anyopaque) void {
        const self: *@This() = @ptrCast(@alignCast(data));
        self.allocator.destroy(self);
    }

    fn helpContent(data: *anyopaque) HelpContent {
        _ = data;
        return .{
            .title = "Description Help",
            .entries = &.{
                .{ .key = "j", .description = "Scroll down" },
                .{ .key = "k", .description = "Scroll up" },
            },
        };
    }

    const vtable = Section.VTable{
        .handleInput = handleInput,
        .update = update,
        .render = render,
        .helpContent = helpContent,
        .deinit = deinit,
    };
};
