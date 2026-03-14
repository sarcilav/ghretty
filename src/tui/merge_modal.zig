const std = @import("std");
const vaxis = @import("vaxis");
const TextInput = vaxis.widgets.TextInput;
const PRMergeAction = @import("../models/pr.zig").PRMergeAction;
const action_modal = @import("action_modal.zig");

pub fn render(
    window: vaxis.Window,
    input: *TextInput,
    selected_action: PRMergeAction,
    error_message: ?[]const u8,
) !void {
    try action_modal.render(window, input, .{
        .title = "Merge Pull Request",
        .subtitle = "\nUse tab to switch actions, type an optional message, press shift-enter to submit.\n",
        .field_label = "\n\n\nMessage\n",
        .action_rows = &.{
            &.{
                actionSegment(.merge_commit, selected_action, "Create Merge Commit"),
                actionSegment(.merge_commit, selected_action, "  "),
                actionSegment(.squash, selected_action, "Squash and Merge"),
                actionSegment(.merge_commit, selected_action, "  "),
                actionSegment(.rebase, selected_action, "Rebase and Merge"),
                actionSegment(.merge_commit, selected_action, "  "),
                actionSegment(.close, selected_action, "Close Pull Request"),
            },
        },
        .placeholder = actionPlaceholder(selected_action),
        .footer_text = footerText(selected_action),
        .error_message = error_message,
        .modal_width = 84,
        .input_box_y = 5,
        .input_box_height = 3,
        .footer_height = 2,
    });
}

fn actionSegment(action: PRMergeAction, selected_action: PRMergeAction, label: []const u8) action_modal.SegmentSpec {
    return .{
        .text = label,
        .selected = action == selected_action and label.len > 2,
    };
}

fn actionPlaceholder(action: PRMergeAction) []const u8 {
    return switch (action) {
        .merge_commit => "Optional merge commit subject",
        .squash => "Optional squash commit subject",
        .rebase => "No custom message for rebase merges",
        .close => "Optional closing comment",
    };
}

fn footerText(action: PRMergeAction) []const u8 {
    return switch (action) {
        .merge_commit => "Create a merge commit on the base branch.",
        .squash => "Squash commits and merge the pull request.",
        .rebase => "Rebase commits and merge the pull request. Message input is ignored.",
        .close => "Close the pull request without merging.",
    };
}
