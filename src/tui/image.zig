const std = @import("std");
const vaxis = @import("vaxis");

// consider using window child to logically handle the position
// const child = window.child(layout.rect(
//     x,
//     y,
//     w,
//     h,
// ));

// const pos = child.screen_coordinates(); // or equivalent offset access

// try kitty_draw_image(
//     writer,
//     image,
//     .{
//         .x = pos.x,
//         .y = pos.y,
//         .max_width = child.width,
//         .max_height = child.height,
//     },
// );
pub fn placeKittyImage(writer: *std.Io.Writer, image_id: u32, window: vaxis.Window) !void {
    const x = window.x_off;
    const y = window.y_off;

    // delete previous placement
    try writer.print("\x1b_Ga=d,i={d},q=2\x1b\\", .{image_id});

    try writer.print(
        "\x1b_Ga=p,i={d},x={d},y={d},q=2\x1b\\",
        .{ image_id, x, y },
    );
}

/// Send base64-encoded image data in chunks using the Kitty protocol.
/// Now includes `q=2` to suppress the terminal's confirmation response.
pub fn sendKittyImage(writer: *std.Io.Writer, image_id: u32, encoded: []const u8, format: u32, original_size: usize) !void {
    const chunk_size = 4096;

    var offset: usize = 0;
    while (offset < encoded.len) {
        const end = @min(offset + chunk_size, encoded.len);
        const chunk = encoded[offset..end];
        const more = end < encoded.len;

        try writer.writeAll("\x1b_G");

        if (offset == 0) {
            // First chunk: include action, ID, format, total size, and silent mode (q=2)
            try writer.print("a=T,i={d},f={d},s={d},q=2", .{ image_id, format, original_size });
            if (more) try writer.print(",m=1", .{});
        } else {
            // Subsequent chunks: action and ID only
            try writer.print("a=T,i={d}", .{image_id});
            if (more) try writer.print(",m=1", .{});
        }

        try writer.writeAll(";");
        try writer.writeAll(chunk);
        try writer.writeAll("\x1b\\");

        offset = end;
    }
    // ensure it isn't auto placed
    try writer.print("\x1b_Ga=d,i={d},q=2\x1b\\", .{image_id});
}
