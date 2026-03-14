const std = @import("std");
const vaxis = @import("vaxis");
const TextInput = vaxis.widgets.TextInput;
const PRReviewAction = @import("../models/pr.zig").PRReviewAction;
const theme = @import("theme.zig");

pub fn render(
    window: vaxis.Window,
    input: *TextInput,
    selected_action: PRReviewAction,
    error_message: ?[]const u8,
) !void {
    const modal_width: u16 = @min(window.width -| 4, 72);
    const modal_height: u16 = @min(window.height -| 2, 12);
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
        .{ .text = "Review Pull Request", .style = theme.header_style },
        .{ .text = "\nSelect action with tab, type an optional note, press shift-enter to submit.\n", .style = theme.muted_style },
    }, .{});

    var actions = modal.child(.{
        .x_off = 1,
        .y_off = 2,
        .width = modal_width -| 4,
        .height = 1,
    });
    actions.clear();
    _ = actions.print(&.{
        actionSegment(.approve, selected_action, "Approve"),
        .{ .text = "  ", .style = theme.normal_style },
        actionSegment(.request_changes, selected_action, "Request Changes"),
        .{ .text = "  ", .style = theme.normal_style },
        actionSegment(.comment, selected_action, "Comment"),
    }, .{});

    _ = modal.print(&.{
        .{ .text = "\n\n\nComment\n", .style = theme.normal_style },
    }, .{});

    var input_box = modal.child(.{
        .x_off = 2,
        .y_off = 4,
        .width = modal_width -| 4,
        .height = 5,
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
            .{ .text = actionPlaceholder(selected_action), .style = theme.muted_style },
        }, .{});
    } else {
        input.drawWithStyle(input_area, theme.normal_style);
    }

    const footer_style = if (error_message != null) theme.error_style else theme.muted_style;
    const footer_text = error_message orelse footerText(selected_action);

    var footer = modal.child(.{
        .x_off = 2,
        .y_off = modal_height -| 3,
        .width = modal_width -| 4,
        .height = 3,
    });
    footer.clear();
    _ = footer.print(&.{
        .{ .text = footer_text, .style = footer_style },
    }, .{});
}

fn actionSegment(action: PRReviewAction, selected_action: PRReviewAction, label: []const u8) vaxis.Segment {
    return .{
        .text = label,
        .style = if (action == selected_action) theme.selected_row_style else theme.normal_style,
    };
}

fn actionPlaceholder(action: PRReviewAction) []const u8 {
    return switch (action) {
        .approve => "Optional approval note",
        .request_changes => "Optional requested changes summary",
        .comment => "Required review comment",
    };
}

fn footerText(action: PRReviewAction) []const u8 {
    return switch (action) {
        .approve => "Submit an approval review.",
        .request_changes => "Submit changes-request review.",
        .comment => "Comments require a note.",
    };
}
