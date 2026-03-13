const std = @import("std");
const vaxis = @import("vaxis");
const Screen = @import("screens/screen.zig").Screen;
const PRListScreen = @import("screens/pr_list.zig").PRListScreen;

// This can contain internal events as well as Vaxis events.
// Internal events can be posted into the same queue as vaxis events to allow
// for a single event loop with exhaustive switching. Booya
const Event = union(enum) {
    key_press: vaxis.Key,
    winsize: vaxis.Winsize,
    focus_in,
};

pub const App = struct {
    allocator: std.mem.Allocator,
    vx: *vaxis.Vaxis,
    tty_buf: []u8,
    tty: *vaxis.Tty,
    current_screen: *Screen,
    screen_stack: std.ArrayListUnmanaged(*Screen),
    should_quit: bool = false,
    loop: vaxis.Loop(Event),

    pub fn init(allocator: std.mem.Allocator) !@This() {
        const buf = try allocator.alloc(u8, 16 * 1024);

        const tty = try allocator.create(vaxis.Tty);
        tty.* = try vaxis.Tty.init(buf);
        errdefer tty.deinit();

        const vx = try allocator.create(vaxis.Vaxis);
        vx.* = try vaxis.init(allocator, .{});
        errdefer vx.deinit(allocator, tty.writer());

        var app = App{
            .allocator = allocator,
            .vx = vx,
            .tty_buf = buf,
            .tty = tty,
            .current_screen = undefined,
            .screen_stack = .{},
            .loop = undefined,
        };

        // Screens
        const pr_list_screen = try PRListScreen.create(allocator);
        try app.screen_stack.append(allocator, pr_list_screen);
        app.current_screen = pr_list_screen;

        // NOW initialize loop using pointers to app fields
        app.loop = .{
            .tty = app.tty,
            .vaxis = app.vx,
        };
        try app.loop.init();

        return app;
    }

    pub fn deinit(self: *@This()) void {
        for (self.screen_stack.items) |screen| {
            screen.deinit();
        }
        self.screen_stack.deinit(self.allocator);
        self.vx.deinit(self.allocator, self.tty.writer());
        self.allocator.destroy(self.vx);
        self.tty.deinit();
        self.allocator.destroy(self.tty);
        self.allocator.free(self.tty_buf);
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
                    // std.debug.print("else", .{});
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
