const vaxis = @import("vaxis");

// ANSI color indices:
// 0: black, 1: red, 2: green, 3: yellow, 4: blue, 5: magenta, 6: cyan, 7: white
// 8-15: bright versions

pub const selected_row_style = vaxis.Style{
    .fg = .{ .index = 0 }, // Black
    .bg = .{ .index = 15 }, // Bright white
    .bold = true,
};

pub const normal_style = vaxis.Style{
    .fg = .{ .index = 7 }, // White
    .bg = .{ .index = 0 }, // Black
};

pub const header_style = vaxis.Style{
    .fg = .{ .index = 6 }, // Cyan
    .bold = true,
    .underline = true,
};

pub const error_style = vaxis.Style{
    .fg = .{ .index = 1 }, // Red
    .bold = true,
};

pub const loading_style = vaxis.Style{
    .fg = .{ .index = 3 }, // Yellow
    .bold = true,
};
