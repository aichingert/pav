const std = @import("std");
const mem = std.mem;
const assert = std.debug.assert;

const png_sig = [_]u8{137, 80, 78, 71, 13, 10, 26, 10};

fn read_u32(pos: *u32, raw_png: []const u8) u32 {
    const i = pos.*;
    const data: u32 = (@as(u32, raw_png[i + 3]) << 24) 
                  | (@as(u32, raw_png[i + 2]) << 16)
                  | (@as(u32, raw_png[i + 1]) << 8)
                  | (@as(u32, raw_png[i ]));
    pos.* += 4;
    return data;
}

pub fn extract_pixels(raw_png: []const u8) void {
    assert(raw_png.len >= 8 and mem.eql(u8, &png_sig, raw_png[0..8]));

    var pos: u32 = 8;

    const width: u32 = read_u32(&pos, raw_png);
    const height: u32 = read_u32(&pos, raw_png);

    std.debug.print("{any} - {any}\n", .{width, height});

}


