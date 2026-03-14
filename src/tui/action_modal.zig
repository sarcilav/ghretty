const std = @import("std");
const vaxis = @import("vaxis");
const TextInput = vaxis.widgets.TextInput;
const theme = @import("theme.zig");

pub const Config = struct {
    title: []const u8,
    subtitle: []const u8,
    field_label: []const u8,
    action_rows: []const []const SegmentSpec,
    placeholder: []const u8,
    footer_text: []const u8,
    error_message: ?[]const u8 = null,
    modal_width: u16 = 80,
    modal_height: u16 = 12,
    input_box_y: u16 = 4,
    input_box_height: u16 = 5,
    footer_height: u16 = 3,
};

pub const SegmentSpec = struct {
    text: []const u8,
    selected: bool = false,
};

pub fn render(window: vaxis.Window, input: *TextInput, config: Config) !void {
    const modal_width: u16 = @min(window.width -| 4, config.modal_width);
    const modal_height: u16 = @min(window.height -| 2, config.modal_height);
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
        .{ .text = config.title, .style = theme.header_style },
        .{ .text = config.subtitle, .style = theme.muted_style },
    }, .{});

    for (config.action_rows, 0..) |row_specs, idx| {
        var actions = modal.child(.{
            .x_off = 1,
            .y_off = @intCast(2 + idx),
            .width = modal_width -| 4,
            .height = 1,
        });
        actions.clear();

        var segments = std.ArrayList(vaxis.Segment){};
        defer segments.deinit(std.heap.page_allocator);

        for (row_specs) |spec| {
            try segments.append(std.heap.page_allocator, .{
                .text = spec.text,
                .style = if (spec.selected) theme.selected_row_style else theme.normal_style,
            });
        }

        _ = actions.print(segments.items, .{});
    }

    _ = modal.print(&.{
        .{ .text = config.field_label, .style = theme.normal_style },
    }, .{});

    var input_box = modal.child(.{
        .x_off = 2,
        .y_off = config.input_box_y,
        .width = modal_width -| 5,
        .height = config.input_box_height,
        .border = .{ .where = .all },
    });
    input_box.clear();

    var input_area = input_box.child(.{
        .x_off = 1,
        .y_off = 0,
        .width = input_box.width -| 2,
        .height = 1,
    });
    input_area.clear();

    if (input.buf.realLength() == 0) {
        _ = input_area.print(&.{
            .{ .text = config.placeholder, .style = theme.muted_style },
        }, .{});
    } else {
        input.drawWithStyle(input_area, theme.normal_style);
    }

    const footer_style = if (config.error_message != null) theme.error_style else theme.muted_style;
    const footer_text = config.error_message orelse config.footer_text;

    var footer = modal.child(.{
        .x_off = 2,
        .y_off = modal_height -| config.footer_height,
        .width = modal_width -| 4,
        .height = config.footer_height,
    });
    footer.clear();
    _ = footer.print(&.{
        .{ .text = footer_text, .style = footer_style },
    }, .{});
}
