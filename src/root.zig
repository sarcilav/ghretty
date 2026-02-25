//! By convention, root.zig is the root source file when making a library.
const std = @import("std");

// Export the main app module
pub const App = @import("app.zig").App;

// Export screen-related modules
pub const Screen = @import("screens/screen.zig").Screen;
pub const PRListScreen = @import("screens/pr_list.zig").PRListScreen;
pub const PRDetailsScreen = @import("screens/pr_details.zig").PRDetailsScreen;

// Export models
pub const models = @import("models/pr.zig");

// Export GitHub client
pub const github = @import("github/client.zig");

// Export TUI components
pub const tui = struct {
    pub const theme = @import("tui/theme.zig");
    pub const components = @import("tui/components.zig");
};

pub fn bufferedPrint() !void {
    // Stdout is for the actual output of your application, for example if you
    // are implementing gzip, then only the compressed bytes should be sent to
    // stdout, not any debugging messages.
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;

    try stdout.print("Run `zig build test` to run the tests.\n", .{});

    try stdout.flush(); // Don't forget to flush!
}

pub fn add(a: i32, b: i32) i32 {
    return a + b;
}

test "basic add functionality" {
    try std.testing.expect(add(3, 7) == 10);
}
