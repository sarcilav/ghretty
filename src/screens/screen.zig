const std = @import("std");
const vaxis = @import("vaxis");

pub const Screen = struct {
    vtable: *VTable,

    pub const VTable = struct {
        handleInput: *const fn(self: *@This(), key: vaxis.Key) anyerror!void,
        update: *const fn(self: *@This()) anyerror!void,
        render: *const fn(self: *@This(), window: vaxis.Window) anyerror!void,
        deinit: *const fn(self: *@This()) void,
    };

    pub fn deinit(self: *@This()) void {
        self.vtable.deinit(self);
    }

    pub fn handleInput(self: *@This(), key: vaxis.Key) anyerror!void {
        try self.vtable.handleInput(self, key);
    }

    pub fn update(self: *@This()) anyerror!void {
        try self.vtable.update(self);
    }

    pub fn render(self: *@This(), window: vaxis.Window) anyerror!void {
        try self.vtable.render(self, window);
    }    
};
