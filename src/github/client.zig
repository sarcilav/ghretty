const std = @import("std");
const PR = @import("../models/pr.zig").PR;
const PRState = @import("../models/pr.zig").PRState;
const FileChange = @import("../models/pr.zig").FileChange;
const git = @import("../models/git.zig");

pub const GitHubClient = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) @This() {
        return @This(){
            .allocator = allocator,
        };
    }

    pub fn fetchPRs(self: *@This()) !std.ArrayList(PR) {
        const result = try self.runGhCommand(&.{ "pr", "list", "--json", "number,title,author,state,isDraft,reviewRequests" });
        defer self.allocator.free(result);

        return try self.parsePRList(result);
    }

    pub fn fetchPRDetails(self: *@This(), pr_number: u32) !PR {
        const result = try self.runGhCommand(&.{ "pr", "view", try std.fmt.allocPrint(self.allocator, "{}", .{pr_number}), "--json", "title,author,state,isDraft,body,files,number" });
        defer self.allocator.free(result);

        return try self.parsePRDetails(result);
    }

    pub fn fetchPRDiff(self: *@This(), pr: PR) !std.ArrayList(git.DiffLine) {
        const raw_diff = try self.runGhCommand(&.{ "pr", "diff", try std.fmt.allocPrint(self.allocator, "{}", .{pr.number}), "--patch" });
        return try self.parsePRDiff(raw_diff);
    }

    fn runGhCommand(self: *@This(), args: []const []const u8) ![]const u8 {
        var process = std.process.Child.init(args, self.allocator);

        const argv = try self.allocator.alloc([]const u8, args.len + 1);
        defer self.allocator.free(argv);
        argv[0] = "gh";
        @memcpy(argv[1..], args);
        process.argv = argv;

        process.stdin_behavior = .Pipe;
        process.stdout_behavior = .Pipe;
        process.stderr_behavior = .Pipe;

        var env = try std.process.getEnvMap(self.allocator);
        defer env.deinit();
        try env.put("TERM", "dumb");
        try env.put("GIT_PAGER", "cat");
        try env.put("PAGER", "cat");
        try env.put("GH_PAGER", "cat");
        try env.put("GH_FORCE_TTY", "0");
        try env.put("NO_COLOR", "1");
        try env.put("CLICOLOR", "0");

        process.env_map = &env;

        try process.spawn();

        const stdout = try process.stdout.?.readToEndAlloc(
            self.allocator,
            std.math.maxInt(usize),
        );

        const stderr = try process.stderr.?.readToEndAlloc(
            self.allocator,
            std.math.maxInt(usize),
        );

        const term = try process.wait();
        switch (term) {
            .Exited => |code| {
                if (code != 0) {
                    std.debug.print("gh command failed with code {}: {s}\n", .{ code, stderr });
                    return error.GhCommandFailed;
                }
            },
            else => {
                std.debug.print("gh command terminated unexpectedly: {s}\n", .{stderr});
                return error.GhCommandFailed;
            },
        }
        return stdout;
    }

    fn parsePRDiff(self: *@This(), raw_diff_str: []const u8) !std.ArrayList(git.DiffLine) {
        var diff_lines = std.ArrayList(git.DiffLine){};
        errdefer {
            diff_lines.deinit(self.allocator);
        }
        var lines = std.mem.splitSequence(u8, raw_diff_str, "\n");
        while (lines.next()) |line| {
            const diff_line = git.DiffLine{
                .text = line,
                .kind = git.classify(line),
            };
            try diff_lines.append(self.allocator, diff_line);
        }
        return diff_lines;
    }

    fn parsePRList(self: *@This(), json_str: []const u8) !std.ArrayList(PR) {
        var parsed = try std.json.parseFromSlice(std.json.Value, self.allocator, json_str, .{ .allocate = .alloc_if_needed });
        defer parsed.deinit();
        var prs = std.ArrayList(PR){};
        errdefer {
            for (prs.items) |*pr| {
                pr.deinit(self.allocator);
            }
            prs.deinit(self.allocator);
        }

        if (parsed.value != .array) {
            return error.InvalidJson;
        }

        for (parsed.value.array.items) |item| {
            const pr = try self.parsePRFromJson(item);
            try prs.append(self.allocator, pr);
        }

        return prs;
    }

    fn parsePRDetails(self: *@This(), json_str: []const u8) !PR {
        var parsed = try std.json.parseFromSlice(std.json.Value, self.allocator, json_str, .{});
        defer parsed.deinit();

        return try self.parsePRFromJson(parsed.value);
    }

    fn parsePRFromJson(self: *@This(), json: std.json.Value) !PR {
        const obj = json.object;

        const number = if (obj.get("number")) |n|
            @as(u32, @intCast(@as(i64, @intCast(n.integer))))
        else
            return error.MissingField;

        const title = if (obj.get("title")) |t|
            try self.allocator.dupe(u8, t.string)
        else
            return error.MissingField;

        const author_obj = obj.get("author") orelse return error.MissingField;
        const author = if (author_obj.object.get("login")) |login|
            try self.allocator.dupe(u8, login.string)
        else
            return error.MissingField;

        const state_str = if (obj.get("state")) |s| s.string else return error.MissingField;
        const state: PRState = if (std.mem.eql(u8, state_str, "OPEN"))
            .open
        else if (std.mem.eql(u8, state_str, "CLOSED"))
            .closed
        else
            .merged;

        const is_draft = if (obj.get("isDraft")) |d| d.bool else false;

        const review_requested = if (obj.get("reviewRequests")) |requests|
            requests.array.items.len > 0
        else
            false;

        var pr = PR{
            .number = number,
            .title = title,
            .author = author,
            .state = state,
            .is_draft = is_draft,
            .review_requested = review_requested,
        };

        // Parse body if present
        if (obj.get("body")) |body_val| {
            if (body_val == .string) {
                pr.body = try self.allocator.dupe(u8, body_val.string);
            }
        }

        // Parse files if present
        if (obj.get("files")) |files_val| {
            if (files_val == .array) {
                var files = std.ArrayList(FileChange){}; //.init(self.allocator);
                for (files_val.array.items) |file_item| {
                    const file_obj = file_item.object;

                    const path = if (file_obj.get("path")) |p|
                        try self.allocator.dupe(u8, p.string)
                    else
                        continue;

                    const additions = if (file_obj.get("additions")) |a|
                        @as(u32, @intCast(@as(i64, @intCast(a.integer))))
                    else
                        0;

                    const deletions = if (file_obj.get("deletions")) |d|
                        @as(u32, @intCast(@as(i64, @intCast(d.integer))))
                    else
                        0;

                    const changes = if (file_obj.get("changes")) |c|
                        @as(u32, @intCast(@as(i64, @intCast(c.integer))))
                    else
                        0;

                    try files.append(self.allocator, FileChange{
                        .path = path,
                        .additions = additions,
                        .deletions = deletions,
                        .changes = changes,
                    });
                }
                pr.files = files;
            }
        }

        return pr;
    }
};

// Test module
test "GitHubClient initialization" {
    const allocator = std.testing.allocator;
    const client = GitHubClient.init(allocator);
    try std.testing.expect(@TypeOf(client) == GitHubClient);
}

test "parse state strings" {
    const allocator = std.testing.allocator;
    const client = GitHubClient.init(allocator);

    // Test state parsing
    const test_json =
        \\{"number": 123, "title": "Test PR", "author": {"login": "testuser"}, "state": "OPEN"}
    ;

    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, test_json, .{});
    defer parsed.deinit();

    const pr = try client.parsePRFromJson(parsed.value);
    defer pr.deinit(allocator);

    try std.testing.expect(pr.state == .open);
    try std.testing.expect(pr.number == 123);
    try std.testing.expectEqualStrings("Test PR", pr.title);
    try std.testing.expectEqualStrings("testuser", pr.author);
}
