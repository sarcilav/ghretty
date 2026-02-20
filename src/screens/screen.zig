const std = @import("std");
const vaxis = @import("vaxis");

pub const Screen = struct {
    allocator: std.mem.Allocator,
    vx: *vaxis.Vaxis,

    pub fn init(comptime T: type, allocator: std.mem.Allocator, vx: *vaxis.Vaxis) !T{
        return T{
            .allocator = allocator,
            .vx = vx,
        };
    }

    pub fn deinit(comptime T: type, self: *T) void {
        _ = self;
    }

    pub fn handleInput(comptime T: type, self: *T, key: vaxis.Key) !void {
        std.debug.print("debug(generic screen): handleInput\r\n", .{});
        _ = self;
        _ = key;
        // TODO: Implement in derived screens
    }

    pub fn update(comptime T: type, self: *T) !void {
        _ = self;
        // TODO: Implement in derived screens
    }

    pub fn render(comptime T: type, self: *T, window: vaxis.Window) !void {
        _ = self;
        _ = window;
        // TODO: Implement in derived screens
    }
};
