const std = @import("std");

pub fn main() !void {
    // Parse command line arguments
    const args = try std.process.argsAlloc(std.heap.page_allocator);
    defer std.process.argsFree(std.heap.page_allocator, args);

    if (args.len < 2) {
        std.debug.print("Usage: {s} <image-file>\n", .{args[0]});
        std.process.exit(1);
    }
    const file_name = args[1];

    // Read the image file
    const file = try std.fs.cwd().openFile(file_name, .{});
    defer file.close();

    const stat = try file.stat();
    const image_bytes = try file.readToEndAlloc(std.heap.page_allocator, stat.size);
    defer std.heap.page_allocator.free(image_bytes);

    // Determine image format from extension
    const format = formatFromExtension(file_name) orelse {
        std.debug.print("Unsupported file extension. Use .png, .jpg, .jpeg, .gif, or .bmp\n", .{});
        std.process.exit(1);
    };

    // Base64 encode the image data
    const base64_encoder = std.base64.standard.Encoder;
    const encoded_len = base64_encoder.calcSize(image_bytes.len);
    const encoded = try std.heap.page_allocator.alloc(u8, encoded_len);
    defer std.heap.page_allocator.free(encoded);
    _ = base64_encoder.encode(encoded, image_bytes);

    // Create an unbuffered writer to stdout (Zig 0.15 style)
    var w = std.fs.File.stdout().writer(&.{});
    const stdout = &w.interface;

    // Add some spacing so the image isn't squashed against the prompt
    try stdout.writeAll("\n");

    // Send the image using the Kitty Graphics Protocol
    try sendKittyImage(stdout, encoded, format, image_bytes.len);

    // Another newline after the image
    try stdout.writeAll("\n");
}

/// Guess image format from file extension.
/// Values correspond to the Kitty graphics protocol's 'f' parameter.
fn formatFromExtension(file_name: []const u8) ?u32 {
    const ext = std.fs.path.extension(file_name);
    if (std.ascii.eqlIgnoreCase(ext, ".png")) return 100; // PNG
    if (std.ascii.eqlIgnoreCase(ext, ".jpg")) return 101; // JPEG
    if (std.ascii.eqlIgnoreCase(ext, ".jpeg")) return 101; // JPEG
    if (std.ascii.eqlIgnoreCase(ext, ".gif")) return 102; // GIF
    if (std.ascii.eqlIgnoreCase(ext, ".bmp")) return 103; // BMP
    return null;
}

/// Send base64-encoded image data in chunks using the Kitty protocol.
/// Now includes `q=2` to suppress the terminal's confirmation response.
fn sendKittyImage(writer: *std.Io.Writer, encoded: []const u8, format: u32, original_size: usize) !void {
    const image_id = 1;
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
}
