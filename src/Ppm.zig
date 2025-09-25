const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;

const utils = @import("utils.zig");
const Image = utils.Image;

const ppm_init: []const u8 = "P3\n";

fn write_number_with_end(comptime T: type, buffer: []u8, pos: *u64, number: T, end: u8) !void {
    const n = try std.fmt.bufPrint(buffer[pos.*..], "{}", .{number});
    pos.* += n.len;
    buffer[pos.*] = end;
    pos.* += 1;
}

pub fn write_image(allocator: Allocator, path: []const u8, image: *Image) !void {
    // NOTE: allocating way too much at the moment
    var buffer: []u8 = try allocator.alloc(u8, 3 * 30 + image.*.pixels.len * 20);

    const file = try std.fs.cwd().createFile(path, .{ .read = true });
    for (ppm_init, 0..) |c, i| {
        buffer[i] = c;
    }

    var ppm_pos: u64 = ppm_init.len;

    try write_number_with_end(u32, buffer, &ppm_pos, image.*.width, ' ');
    try write_number_with_end(u32, buffer, &ppm_pos, image.*.height, ' ');
    try write_number_with_end(u32, buffer, &ppm_pos, 255, '\n');

    for (image.pixels) |pixel| {
        try write_number_with_end(u32, buffer, &ppm_pos, (pixel >> 16) & 0xFF, ' ');
        try write_number_with_end(u32, buffer, &ppm_pos, (pixel >> 8) & 0xFF, ' ');
        try write_number_with_end(u32, buffer, &ppm_pos, (pixel >> 0) & 0xFF, ' ');
    }

    try file.writeAll(buffer[0..ppm_pos]);
    file.close();
    allocator.free(buffer);
    std.debug.print("[INFO] written=`{s}` size=`{d}kb`\n", .{path, ppm_pos / 1000});
}

