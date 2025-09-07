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

pub fn write_png(allocator: Allocator, width: u32, height: u32, plte: Png.PLTE, idat: Png.IDAT) !void {
    const file = try std.fs.cwd().createFile("image.ppm", .{ .read = true });
    var buffer: []u8 = try allocator.alloc(u8, 3 * 30 + width * height * 10);

    for (ppm_init, 0..) |c, i| {
        buffer[i] = c;
    }

    var pos: u64 = ppm_init.len;

    try write_number_with_end(u32, buffer, &pos, width, ' ');
    try write_number_with_end(u32, buffer, &pos, height, '\n');
    try write_number_with_end(u32, buffer, &pos, 255, '\n');

    // [width * height]u8

    std.debug.print("{any} | {any}\n", .{idat.size, width * height});
    assert(idat.size > width * height);
    var i: u64 = 0;
    while (i < width * height) {
        const color: u24 = plte.palette[idat.data[i]];
        const r: u24 = color >> 16;
        const g: u24 = (color >> 8) & 0xFF;
        const b: u24 = (color) & 0xFF;

        try write_number_with_end(u24, buffer, &pos, r, ' ');
        try write_number_with_end(u24, buffer, &pos, g, ' ');
        try write_number_with_end(u24, buffer, &pos, b, ' ');
            
        i += 1;
    }

    try file.writeAll(buffer[0..pos]);
    file.close();
    allocator.free(buffer);
}
