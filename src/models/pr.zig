const std = @import("std");

pub const PRState = enum {
    open,
    closed,
    merged,
};

pub const PRReviewAction = enum {
    approve,
    request_changes,
    comment,
};

pub const PR = struct {
    number: u32,
    title: []const u8,
    author: []const u8,
    state: PRState,
    is_draft: bool,
    review_requested: bool,
    body: ?[]const u8 = null,
    files: ?std.ArrayList(FileChange) = null,

    pub fn deinit(self: *PR, allocator: std.mem.Allocator) void {
        allocator.free(self.title);
        allocator.free(self.author);

        if (self.body) |body| {
            allocator.free(body);
        }

        if (self.files) |*files| {
            for (files.items) |*file| {
                file.deinit(allocator);
            }
            files.deinit(allocator);
        }
    }
};

pub const FileChange = struct {
    path: []const u8,
    additions: u32,
    deletions: u32,
    changes: u32,

    pub fn deinit(self: *FileChange, allocator: std.mem.Allocator) void {
        allocator.free(self.path);
    }
};

// Test module
test "PR model" {
    const allocator = std.testing.allocator;

    var pr = PR{
        .number = 123,
        .title = try allocator.dupe(u8, "Test PR"),
        .author = try allocator.dupe(u8, "testuser"),
        .state = .open,
        .is_draft = false,
        .review_requested = true,
    };
    defer pr.deinit(allocator);

    try std.testing.expect(pr.number == 123);
    try std.testing.expectEqualStrings("Test PR", pr.title);
    try std.testing.expect(pr.state == .open);
    try std.testing.expect(pr.review_requested == true);
}
