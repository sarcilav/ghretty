const std = @import("std");
const vaxis = @import("vaxis");

pub const HelpEntry = struct {
    key: []const u8,
    description: []const u8,
};

pub const HelpContent = struct {
    title: []const u8,
    entries: []const HelpEntry,
};

pub const Section = struct {
    vtable: *const VTable,
    data: *anyopaque,

    pub const VTable = struct {
        handleInput: *const fn (data: *anyopaque, key: vaxis.Key) void,
        update: *const fn (data: *anyopaque) anyerror!void,
        render: *const fn (data: *anyopaque, window: vaxis.Window) anyerror!void,
        helpContent: *const fn (data: *anyopaque) HelpContent,
        deinit: *const fn (data: *anyopaque) void,
    };

    pub fn handleInput(self: *@This(), key: vaxis.Key) void {
        self.vtable.handleInput(self.data, key);
    }

    pub fn update(self: *@This()) !void {
        try self.vtable.update(self.data);
    }

    pub fn render(self: *@This(), window: vaxis.Window) !void {
        try self.vtable.render(self.data, window);
    }

    pub fn helpContent(self: *@This()) HelpContent {
        return self.vtable.helpContent(self.data);
    }

    pub fn deinit(self: *@This()) void {
        self.vtable.deinit(self.data);
    }
};
