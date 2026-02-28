const std = @import("std");

pub fn placeKittyImage(
    writer: *std.Io.Writer,
    image_id: u32,
    cell_row: u16,
    cell_col: u16,
    cell_width: u16,
) !void {
    // delete previous placement
    try writer.print("\x1b_Ga=d,i={d},q=2\x1b\\", .{image_id});

    // Position cursor
    try writer.print("\x1b[{d};{d}H", .{ cell_row, cell_col });
    try writer.print(
        "\x1b_Ga=p,i={d},c={d},q=2\x1b\\",
        .{ image_id, cell_width },
    );
}

/// Send base64-encoded image data in chunks using the Kitty protocol.
/// Now includes `q=2` to suppress the terminal's confirmation response.
/// Remove the auto placed image after transmission
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
