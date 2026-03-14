const std = @import("std");
const vaxis = @import("vaxis");
const TextInput = vaxis.widgets.TextInput;
const PRReviewAction = @import("../models/pr.zig").PRReviewAction;
const action_modal = @import("action_modal.zig");

pub fn render(
    window: vaxis.Window,
    input: *TextInput,
    selected_action: PRReviewAction,
    error_message: ?[]const u8,
) !void {
    try action_modal.render(window, input, .{
        .title = "Review Pull Request",
        .subtitle = "\nSelect action with tab, type an optional note, press shift-enter to submit.\n",
        .field_label = "\n\n\nComment\n",
        .action_rows = &.{
            &.{
                actionSegment(.approve, selected_action, "Approve"),
                actionSegment(.approve, selected_action, "  "),
                actionSegment(.request_changes, selected_action, "Request Changes"),
                actionSegment(.approve, selected_action, "  "),
                actionSegment(.comment, selected_action, "Comment"),
            },
        },
        .placeholder = actionPlaceholder(selected_action),
        .footer_text = footerText(selected_action),
        .error_message = error_message,
    });
}

fn actionSegment(action: PRReviewAction, selected_action: PRReviewAction, label: []const u8) action_modal.SegmentSpec {
    return .{
        .text = label,
        .selected = action == selected_action and label.len > 2,
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
