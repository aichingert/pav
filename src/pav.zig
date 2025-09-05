const std = @import("std");

pub const Png = @import("Png.zig");


pub fn main() !void {
    const file = try std.fs.cwd().openFile("../image.png", .{});
    defer file.close();

    var raw_data: [4 * 1024 * 1024]u8 = undefined;
    var reader = std.fs.File.Reader.init(file, &raw_data);
    const read_len = try reader.read(&raw_data);

    std.debug.print("{d}\n", .{read_len});
    Png.extract_pixels(&raw_data);
}


