const std = @import("std");

const utils = @import("utils.zig");
const read = utils.read;
const read_slice = utils.read_slice;

const mem = std.mem;
const assert = std.debug.assert;
const Allocator = mem.Allocator;

const webp_riff = [_]u8{'R', 'I', 'F', 'F'};
const webp_hedr = [_]u8{'W', 'E', 'B', 'P'};

pub fn extract_pixels(allocator: Allocator, raw_webp: []const u8) void {
    var pos: u32 = 0;
    const c_riff = read_slice(raw_webp, &pos, 4);
    const c_size = read(u32, raw_webp, &pos);
    const c_webp = read_slice(raw_webp, &pos, 4);
    assert(mem.eql(u8, &webp_riff, c_riff) and mem.eql(u8, &webp_hedr, c_webp));

    std.debug.print("{s} {any} - {s}\n", .{c_riff, c_size, c_webp});

    _ = allocator;

}


