const std = @import("std");

const Png = @import("Png.zig");

const assert = std.debug.assert;
const Allocator = std.mem.Allocator;

const ppm_init: []const u8 = "P3\n";

fn write_number_with_end(comptime T: type, buffer: []u8, pos: *u64, number: T, end: u8) !void {
    const n = try std.fmt.bufPrint(buffer[pos.*..], "{}", .{number});
    pos.* += n.len;
    buffer[pos.*] = end;
    pos.* += 1;
}

pub fn write_pixel_buffer(allocator: Allocator, width: u32, height: u32, pixel_buffer: []u8) !void {
    // NOTE: allocating way too much at the moment
    var buffer: []u8 = try allocator.alloc(u8, 3 * 30 + pixel_buffer.len * 4);

    const file = try std.fs.cwd().createFile("image.ppm", .{ .read = true });
    for (ppm_init, 0..) |c, i| {
        buffer[i] = c;
    }

    var ppm_pos: u64 = ppm_init.len;

    try write_number_with_end(u32, buffer, &ppm_pos, width, ' ');
    try write_number_with_end(u32, buffer, &ppm_pos, height, ' ');
    try write_number_with_end(u32, buffer, &ppm_pos, 255, '\n');

    for (pixel_buffer) |pixel| {
        try write_number_with_end(u8, buffer, &ppm_pos, pixel, ' ');
    }

    try file.writeAll(buffer[0..ppm_pos]);
    file.close();
    allocator.free(buffer);

}

