const std = @import("std");
const vaxis = @import("vaxis");
const Screen = @import("screens/screen.zig").Screen;
const PRListScreen = @import("screens/pr_list.zig").PRListScreen;
const PRDetailsScreen = @import("screens/pr_details.zig").PRDetailsScreen;
const image = @import("tui/image.zig");
// This can contain internal events as well as Vaxis events.
// Internal events can be posted into the same queue as vaxis events to allow
// for a single event loop with exhaustive switching. Booya
const Event = union(enum) {
    key_press: vaxis.Key,
    winsize: vaxis.Winsize,
    focus_in,
    foo: u8,
};

pub const App = struct {
    allocator: std.mem.Allocator,
    vx: vaxis.Vaxis,
    tty_buf: [16 * 1024]u8,
    tty: vaxis.Tty,
    current_screen: *Screen,
    screen_stack: std.ArrayListUnmanaged(*Screen),
    should_quit: bool = false,
    loop: vaxis.Loop(Event),

    pub fn init(allocator: std.mem.Allocator) !@This() {
        var buf: [16 * 1024]u8 = undefined;
        var tty = try vaxis.Tty.init(&buf);
        errdefer tty.deinit();

        var vx = try vaxis.init(allocator, .{});
        errdefer vx.deinit(allocator, tty.writer());

        var screen_stack = std.ArrayListUnmanaged(*Screen){};

        // Create initial screen
        const pr_list_screen = try PRListScreen.create(allocator);

        try screen_stack.append(allocator, pr_list_screen);

        var loop: vaxis.Loop(Event) = .{
            .tty = &tty,
            .vaxis = &vx,
        };
        try loop.init();

        return @This(){
            .allocator = allocator,
            .vx = vx,
            .tty_buf = buf,
            .tty = tty,
            .current_screen = pr_list_screen,
            .screen_stack = screen_stack,
            .loop = loop,
        };
    }

    pub fn deinit(self: *@This()) void {
        // 1️⃣ Deinit all screens
        for (self.screen_stack.items) |screen| {
            screen.deinit();
        }
        self.screen_stack.deinit(self.allocator);
        self.vx.deinit(self.allocator, self.tty.writer());
        self.tty.deinit();
        //self.current_screen.deinit(); it is deinit as part of the stack
    }

    pub fn run(self: *@This()) !void {
        // Start the read loop. This puts the terminal in raw mode and begins
        // reading user input
        try self.loop.start();
        defer self.loop.stop();
        try self.vx.queryTerminal(self.tty.writer(), 1 * std.time.ns_per_s);

        while (!self.should_quit) {
            const event = self.loop.nextEvent();
            switch (event) {
                .key_press => |key| {
                    if (key.matches('q', .{ .ctrl = true })) {
                        self.should_quit = true;
                        continue;
                    } else if (key.matches(vaxis.Key.enter, .{})) {
                        const new_screen = try self.current_screen.navigateInto();
                        try self.navigateTo(new_screen);
                    } else if (key.matches('q', .{})) {
                        self.navigateBack();
                    } else {
                        try self.current_screen.handleInput(key);
                    }
                },
                .winsize => |ws| try self.vx.resize(self.allocator, self.tty.writer(), ws),
                else => {
                    std.debug.print("else", .{});
                },
            }

            const win = self.vx.window();
            win.clear();

            // Update
            try self.current_screen.update();

            // Render
            try self.current_screen.render(win);
            try self.vx.render(self.tty.writer());
        }
    }

    pub fn navigateTo(self: *@This(), screen: *Screen) !void {
        if (screen != self.current_screen) {
            try self.screen_stack.append(self.allocator, screen);
            self.current_screen = screen;
        }
    }

    pub fn navigateBack(self: *@This()) void {
        if (self.screen_stack.items.len > 1) {
            if (self.screen_stack.pop()) |removed_screen| {
                removed_screen.deinit();
            }

            self.current_screen = self.screen_stack.items[self.screen_stack.items.len - 1];
        }
    }
};
