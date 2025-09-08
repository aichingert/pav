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

pub fn write_png(allocator: Allocator, ihdr: Png.IHDR, plte: Png.PLTE, idat: Png.IDAT) !void {
    const file = try std.fs.cwd().createFile("image.ppm", .{ .read = true });
    var buffer: []u8 = try allocator.alloc(u8, 3 * 30 + ihdr.width * ihdr.height * 3 * 10);

    for (ppm_init, 0..) |c, i| {
        buffer[i] = c;
    }

    var pos: u64 = ppm_init.len;

    try write_number_with_end(u32, buffer, &pos, ihdr.width, ' ');
    try write_number_with_end(u32, buffer, &pos, ihdr.height, '\n');
    try write_number_with_end(u32, buffer, &pos, 255, '\n');

    var adv: u64 = 0;
    var bpp: u64 = 0;

    if (ihdr.color_type == 3) {
        adv = 1;
        bpp = 1;
    } else if (ihdr.color_type == 2) {
        adv = 3;
        bpp = 3;
    } else if (ihdr.color_type == 6) {
        adv = 4;
        bpp = 4;
    } else {
        assert(false);
    }

    const size: u64 = adv * ihdr.width * ihdr.height;
    assert(idat.size >= size);
    std.debug.print("{any} - {any}\n", .{idat.size, ihdr.width * ihdr.height + ihdr.height});

    var cnt: u64 = 0;
    var i: u64 = 0;
    while (i < ihdr.height) {
        var j: u64 = 0;

        if (idat.data[i * ihdr.width * adv + i] == 1) {
            var f: u64 = 1;
            const o: u64 = i * ihdr.width * adv + i;

            while (f < ihdr.width * adv) {
                var t: u64 = 0;

                while (t < bpp) {
                    const previous: u16 = if (f < 1 + bpp) 0 else @intCast(idat.data[f + o - bpp]);
                    const current: u16 = @intCast(idat.data[f + o]);
                    const corrected: u16 = (current + previous) % 256;
                    const value: u8 = @intCast(corrected);

                    idat.data[f + o] = value;
                    t += 1;
                    f += 1;
                }
            }
        } else if (idat.data[i * ihdr.width * adv + i] == 4) {
            std.debug.print("here\n", .{});
            var f: u64 = 1;
            const o: u64 = i * ihdr.width * adv + i;

            while (f < ihdr.width * adv) {
                var t: u64 = 0;

                while (t < bpp) {
                    const a: i16 = if (f == 1) 0 else @intCast(idat.data[f + o - bpp]);
                    const b: i16 = if (o == 0) 0 else @intCast(idat.data[f + o - ihdr.width * adv + 1]);
                    const c: i16 = if (f == 1 or o == 0) 0 else @intCast(idat.data[f + o - bpp - ihdr.width * adv + 1]);

                    const p: i16 = a + b - c;
                    const pa: u16 = @abs(p - a);
                    const pb: u16 = @abs(p - b);
                    const pc: u16 = @abs(p - c);

                    var value: u16 = 0;
                    if (pa <= pb and pa <= pc) {
                        value = @intCast(a);
                    } else if (pb <= pc) {
                        value = @intCast(b);
                    } else {
                        value = @intCast(c);
                    }

                    value = ((value + idat.data[f + o]) % 256);
                    idat.data[f + o] = @intCast(value);
                    t += 1;
                    f += 1;
                }
            }

        } else if (idat.data[i * ihdr.width * adv + i] != 0) {
            std.debug.print("{any}\n", .{idat.data[i * ihdr.width * adv + i]});
        }

        
        while (j < ihdr.width * adv) {
            cnt += adv;
            var r: u24 = 0;
            var g: u24 = 0;
            var b: u24 = 0;

            if (ihdr.color_type == 2 or ihdr.color_type == 6) {
                r = idat.data[i * ihdr.width * adv + i + j];
                g = idat.data[i * ihdr.width * adv + i + j + 1];
                b = idat.data[i * ihdr.width * adv + i + j + 2];

                if (ihdr.color_type == 6) {
                    const value = @as(f32, @floatFromInt(idat.data[i * ihdr.width * adv + i + j + 3]));
                    const alpha = value / 255.0;

                    const rf = @as(f32, @floatFromInt(r)) * alpha;
                    const gf = @as(f32, @floatFromInt(g)) * alpha;
                    const bf = @as(f32, @floatFromInt(b)) * alpha;
                    r = @intFromFloat(rf);
                    g = @intFromFloat(gf);
                    b = @intFromFloat(bf);
                }
            } else {
                const color: u24 = plte.palette[idat.data[i * ihdr.width + i + j]];
                r = color >> 16;
                g = (color >> 8) & 0xFF;
                b = (color) & 0xFF;
            }
            
            try write_number_with_end(u24, buffer, &pos, r, ' ');
            try write_number_with_end(u24, buffer, &pos, g, ' ');
            try write_number_with_end(u24, buffer, &pos, b, ' ');

            j += adv;
        }

        //std.debug.print("{any} - {any} - {any} - {any}\n", .{ihdr.width * adv, cnt, j, ihdr.width * ihdr.height * adv - ihdr.height});
        i += 1;
    }

    try file.writeAll(buffer[0..pos]);
    file.close();
    allocator.free(buffer);
}
