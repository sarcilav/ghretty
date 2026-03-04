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
        const pr_str = try std.fmt.allocPrint(self.allocator, "{}", .{pr_number});
        defer self.allocator.free(pr_str);

        const result = try self.runGhCommand(&.{ "pr", "view", pr_str, "--json", "title,author,state,isDraft,body,files,number" });
        defer self.allocator.free(result);

        return try self.parsePRDetails(result);
    }

    pub fn fetchPRDiff(self: *@This(), pr: PR) !std.ArrayList(git.FileDiff) {
        const pr_str = try std.fmt.allocPrint(self.allocator, "{}", .{pr.number});
        defer self.allocator.free(pr_str);

        const raw_diff = try self.runGhCommand(&.{ "pr", "diff", pr_str }); //, "--patch" });
        defer self.allocator.free(raw_diff);

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
        defer self.allocator.free(stderr);

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

    fn parsePRDiff(self: *@This(), raw_diff_str: []const u8) !std.ArrayList(git.FileDiff) {
        var file_diffs = std.ArrayList(git.FileDiff){};
        errdefer {
            for (file_diffs.items) |*file_diff| {
                file_diff.deinit(self.allocator);
            }
            file_diffs.deinit(self.allocator);
        }

        var current_file: ?git.FileDiff = null;
        var current_hunk: ?git.Hunk = null;

        var lines = std.mem.splitScalar(u8, raw_diff_str, '\n');

        while (lines.next()) |raw_line| {
            const line = std.mem.trimRight(u8, raw_line, "\r");
            //if (line.len == 0) continue; // Skip empty lines

            // Check for file header
            if (std.mem.startsWith(u8, line, "diff --git")) {
                // Save previous file if exists
                if (current_file) |*file| {
                    // Save previous hunk if exists
                    if (current_hunk) |*hunk| {
                        try file.hunks.append(self.allocator, hunk.*);
                        current_hunk = null;
                    }
                    try file_diffs.append(self.allocator, file.*);
                    current_file = null;
                }

                // Extract filename from "diff --git a/path/to/file b/path/to/file"
                if (std.mem.indexOf(u8, line, " b/")) |b_pos| {
                    const file_start = b_pos + 3; // Skip " b/"
                    const file_end = line.len;
                    const file_path = line[file_start..file_end];

                    current_file = git.FileDiff{
                        .file_path = try self.allocator.dupe(u8, file_path),
                        .hunks = std.ArrayList(git.Hunk){},
                    };
                }
                continue;
            }

            // Check for hunk header
            if (std.mem.startsWith(u8, line, "@@")) {
                // Save previous hunk if exists
                if (current_hunk) |*hunk| {
                    if (current_file) |*file| {
                        try file.hunks.append(self.allocator, hunk.*);
                    }
                    current_hunk = null;
                }

                // Start new hunk
                const safe_header = try escapeForDisplay(self.allocator, line);
                current_hunk = git.Hunk{
                    .header = safe_header,
                    .lines = std.ArrayList(git.DiffLine){},
                };
                continue;
            }

            // Handle regular diff lines
            if (current_hunk) |*hunk| {
                const kind = git.classify(line);
                const safe_line = try escapeForDisplay(self.allocator, line);
                try hunk.lines.append(self.allocator, git.DiffLine{
                    .kind = kind,
                    .text = safe_line,
                });
            }
        }

        // Save the last file and hunk
        if (current_hunk) |*hunk| {
            if (current_file) |*file| {
                try file.hunks.append(self.allocator, hunk.*);
            }
        }
        if (current_file) |*file| {
            try file_diffs.append(self.allocator, file.*);
        }

        return file_diffs;
    }

    fn escapeForDisplay(
        allocator: std.mem.Allocator,
        input: []const u8,
    ) ![]u8 {
        const hex = comptime "0123456789abcdef";

        // ---------- PASS 1: compute final size ----------
        var out_len: usize = 0;

        for (input) |b| {
            if (b == 0x1b or
                (b < 0x20 and b != '\n' and b != '\t') or
                b == 0x7f)
            {
                out_len += 4; // "\xHH"
            } else {
                out_len += 1;
            }
        }

        // ---------- Allocate exactly once ----------
        var out = try allocator.alloc(u8, out_len);

        // ---------- PASS 2: fill ----------
        var j: usize = 0;

        for (input) |b| {
            if (b == 0x1b or
                (b < 0x20 and b != '\n' and b != '\t') or
                b == 0x7f)
            {
                out[j] = '\\';
                j += 1;
                out[j] = 'x';
                j += 1;
                out[j] = hex[b >> 4];
                j += 1;
                out[j] = hex[b & 0xF];
                j += 1;
            } else {
                out[j] = b;
                j += 1;
            }
        }

        return out;
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
