const std = @import("std");
const ghretty = @import("ghretty");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize and run the TUI app
    var app = try ghretty.App.init(allocator);
    defer app.deinit();

    try app.run();
}
