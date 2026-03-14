const std = @import("std");
const vaxis = @import("vaxis");
const theme = @import("theme.zig");
const HelpEntry = @import("section.zig").HelpEntry;

pub fn render(window: vaxis.Window, title: []const u8, entries: []const HelpEntry) !void {
    const content_width = computeContentWidth(title, entries);
    const modal_width = @min(window.width -| 4, @max(@as(u16, 36), content_width + 6));
    const modal_height = @min(window.height -| 2, @as(u16, @intCast(entries.len + 5)));
    const x = if (window.width > modal_width) (window.width - modal_width) / 2 else 0;
    const y = if (window.height > modal_height) (window.height - modal_height) / 2 else 0;

    var modal = window.child(.{
        .x_off = x,
        .y_off = y,
        .width = modal_width,
        .height = modal_height,
        .border = .{ .where = .all },
    });
    modal.clear();

    _ = modal.print(&.{
        .{
            .text = title,
            .style = theme.header_style,
        },
        .{
            .text = "\n",
            .style = theme.normal_style,
        },
    }, .{});

    for (entries, 0..) |entry, idx| {
        var row = modal.child(.{
            .x_off = 1,
            .y_off = @intCast(idx + 2),
            .width = modal_width -| 2,
            .height = 1,
        });
        _ = row.print(&.{
            .{ .text = padKey(entry.key), .style = theme.selected_row_style },
            .{ .text = "  ", .style = theme.normal_style },
            .{ .text = entry.description, .style = theme.normal_style },
        }, .{});
    }
}

fn computeContentWidth(title: []const u8, entries: []const HelpEntry) u16 {
    var width: usize = title.len;
    for (entries) |entry| {
        width = @max(width, 4 + entry.key.len + entry.description.len);
    }
    return @intCast(@min(width, std.math.maxInt(u16)));
}

fn padKey(key: []const u8) []const u8 {
    return switch (key.len) {
        1 => switch (key[0]) {
            'j' => " j ",
            'k' => " k ",
            'v' => " v ",
            'm' => " m ",
            'd' => " d ",
            'f' => " f ",
            'r' => " r ",
            '?' => " ? ",
            'q' => " q ",
            else => key,
        },
        3 => if (std.mem.eql(u8, key, "tab")) "tab" else key,
        else => key,
    };
}
