const std = @import("std");
const vaxis = @import("vaxis");

pub const Section = struct {
    vtable: *const VTable,
    data: *anyopaque,

    pub const VTable = struct {
        handleInput: *const fn (data: *anyopaque, key: vaxis.Key) void,
        update: *const fn (data: *anyopaque) anyerror!void,
        render: *const fn (data: *anyopaque, window: vaxis.Window) anyerror!void,
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

    pub fn deinit(self: *@This()) void {
        self.vtable.deinit(self.data);
    }
};
