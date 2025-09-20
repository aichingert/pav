const std = @import("std");
const z   = @cImport(
    @cInclude("zlib.h")
);

const utils = @import("utils.zig");
const read = utils.read;
const read_slice = utils.read_slice;
const Image = utils.Image;
const RGB = utils.RGB;
const RGBA = utils.RGBA;

const mem = std.mem;
const assert = std.debug.assert;
const Allocator = mem.Allocator;

const png_sig   = [_]u8{137, 80, 78, 71, 13, 10, 26, 10};
const png_ihdr  = [_]u8{'I', 'H', 'D', 'R'};
const png_plte  = [_]u8{'P', 'L', 'T', 'E'};
const png_idat  = [_]u8{'I', 'D', 'A', 'T'};
const png_iend  = [_]u8{'I', 'E', 'N', 'D'};

pub const IHDR = struct {
    width: u32,
    height: u32,

    bit_depth: u8,
    color_type: u8,
    compression_method: u8,
    filter_method: u8,
    interlace_method: u8,

    fn get_bits_per_pixel(self: *IHDR) u8 {
        // TODO: support sub byte pixels
        assert(self.*.bit_depth > 7);

        switch (self.*.color_type) {
            0 => assert(self.*.bit_depth == 1 or self.*.bit_depth == 2 
                     or self.*.bit_depth == 4 or self.*.bit_depth == 8
                     or self.*.bit_depth == 16),
            3 => assert(self.*.bit_depth == 1 or self.*.bit_depth == 2
                     or self.*.bit_depth == 4 or self.*.bit_depth == 8),
            2 => {
                assert(self.*.bit_depth == 8 or self.*.bit_depth == 16);
                return self.*.bit_depth / 8 * RGB;
            },
            4, 6 => {
                assert(self.*.bit_depth == 8 or self.*.bit_depth == 16);
                return self.*.bit_depth / 8 * RGBA;
            },
            else => {
                std.debug.print("ERROR: invalid color_type={any}\n", .{self.*.color_type});
                std.process.exit(1);
            }
        }
 
        return self.*.bit_depth / 8;
    }

    fn read_chunk(raw_png: []const u8, pos: *u32) IHDR {
        const length = read(u32, raw_png, pos);
        assert(length < raw_png.len - pos.*);
        const chunk_type = read_slice(raw_png, pos, 4);

        // NOTE: png has to start with ihdr chunk
        assert(mem.eql(u8, &png_ihdr, chunk_type));

        const width = read(u32, raw_png, pos);
        const height = read(u32, raw_png, pos);

        // TODO: maybe check for validity as compression can only be 1 
        const bit_depth = read(u8, raw_png, pos);
        const color_type = read(u8, raw_png, pos);
        const compression_method = read(u8, raw_png, pos);
        const filter_method = read(u8, raw_png, pos);
        const interlace_method = read(u8, raw_png, pos);

        const crc = read(u32, raw_png, pos);
        _ = crc;

        return IHDR{
            .width = width,
            .height = height,
            .bit_depth = bit_depth,
            .color_type = color_type,
            .compression_method = compression_method,
            .filter_method = filter_method,
            .interlace_method = interlace_method,
        };
    }
};

pub const PLTE = struct {
    palette: [256]u24,
    palette_size: u32,

    fn read_chunk(raw_png: []const u8, pos: *u32, len: u32) PLTE {
        assert(len % 3 == 0);

        var palette: [256]u24 = undefined;
        var i: u32 = 0;

        while (i < len / 3) {
            palette[i] = read(u24, raw_png, pos);
            i += 1;
        }

        return PLTE{
            .palette = palette,
            .palette_size = len / 3,
        };
    }
};

pub const IDAT = struct {
    data: []u8,
    size: u64,

    fn get_color_value(self: *IDAT, ihdr: *IHDR, plte: *PLTE, pos: *u64) u32 {
        switch (ihdr.*.color_type) {
            0, 4 => assert(false),
            2, 6 => {
                var r = @as(u32, self.*.data[pos.* + 0]);
                var g = @as(u32, self.*.data[pos.* + 1]);
                var b = @as(u32, self.*.data[pos.* + 2]);

                if (ihdr.*.color_type == 6) {
                    const value = @as(f32, @floatFromInt(self.*.data[pos.* + 3]));
                    const alpha = value / 255.0;

                    const rf = @as(f32, @floatFromInt(r)) * alpha;
                    const gf = @as(f32, @floatFromInt(g)) * alpha;
                    const bf = @as(f32, @floatFromInt(b)) * alpha;
                    r = @intFromFloat(rf);
                    g = @intFromFloat(gf);
                    b = @intFromFloat(bf);
                    pos.* += 4;
                } else {
                    pos.* += 3;
                }

                return r << 16 | g << 8 | b;
            },
            3 => {
                const index: u8  = self.*.data[pos.*];
                const color: u32 = plte.palette[index];
                pos.* += 1;
                return color;
            },
            else => {
                std.debug.print("ERROR: invalid color_type=`{any}`\n", .{ihdr.*.color_type});
                std.process.exit(1);
            }
        }

        return 0;
    }

    fn read_chunk(allocator: Allocator, raw_png: []const u8, pos: *u32, length: u32) IDAT {
        // TODO: implement chunk reading properly with fixed size buffers
        const alloc_size: u32 = 1 << 31;
        const alloc_buff = allocator.alloc(u8, alloc_size) catch |err| { 
            std.debug.print("ERROR: allocating `{any}`\n", .{err}); 
            std.process.exit(1);
        };

        var infstream = z.z_stream{
            .avail_in = length,
            .next_in = @constCast(raw_png[pos.*..pos.* + length]).ptr,
            .avail_out = alloc_size,
            .next_out = alloc_buff.ptr,
        };

        const init_res = z.inflateInit(&infstream);
        assert(init_res == z.Z_OK);
        pos.* += length;
        var crc = read(u32, raw_png, pos);

        while (true) {
            const infl_res = z.inflate(&infstream, z.Z_NO_FLUSH);
            assert(infl_res == z.Z_OK or infl_res == z.Z_STREAM_END);

            if          (infl_res == z.Z_STREAM_END) {
                const iend_res = z.inflateEnd(&infstream);
                assert(iend_res == z.Z_OK);
                pos.* -= 4;

                return IDAT{
                    .size = infstream.total_out,
                    .data = alloc_buff,
                };
            }

            const len = read(u32, raw_png, pos);
            assert(len < raw_png.len - pos.*);
            pos.* += 4;

            infstream.avail_in = len;
            infstream.next_in = @constCast(raw_png[pos.*..pos.* + len]).ptr;
            pos.* += len;
            crc = read(u32, raw_png, pos);
        }
    }
};

fn get_filter_type(idat: *IDAT, ihdr: *IHDR, line: u32) u8 {
    return idat.data[get_start_of_line(ihdr, line)];
}

fn get_line_width(ihdr: *IHDR) u64 {
    return @as(u64, ihdr.*.width) * @as(u64, ihdr.get_bits_per_pixel());
}

fn get_start_of_line(ihdr: *IHDR, line: u32) u64 {
    return @as(u64, line) * get_line_width(ihdr) + @as(u64, line);
}

fn apply_filter(ihdr: *IHDR, plte: *PLTE, idat: *IDAT, line: *u32, pixel_buffer: []u32) void {
    const filter: u8 = get_filter_type(idat, ihdr, line.*);

    switch (filter) {
        0 => copy_scanline(ihdr, plte, idat, line.*, pixel_buffer),
        1 => subtract_filter(ihdr, plte, idat, line.*, true, pixel_buffer),
        2 => subtract_filter(ihdr, plte, idat, line.*, false, pixel_buffer),
        3 => average_filter(ihdr, plte, idat, line.*, pixel_buffer),
        4 => paeth_filter(ihdr, plte, idat, line.*, pixel_buffer),
        else => {
            std.debug.print("ERROR: invalid filter algorithm=`{any}`\n", .{filter});
            std.process.exit(1);
        }
    }

    line.* += 1;
}

fn copy_scanline(ihdr: *IHDR, plte: *PLTE, idat: *IDAT, line: u32, pixel_buffer: []u32) void {
    const beg = get_start_of_line(ihdr, line) + 1;
    const bpp = ihdr.get_bits_per_pixel();
    var pos = beg;
    var idx: u64 = line * ihdr.*.width;

    while (pos - beg < ihdr.*.width * bpp) : (idx += 1) {
        const color = idat.get_color_value(ihdr, plte, &pos);
        pixel_buffer[idx] = color;
    }
}

// NOTE: there are two subtract filters (left and up)
fn subtract_filter(ihdr: *IHDR, plte: *PLTE, idat: *IDAT, line: u32, is_left: bool, pixel_buffer: []u32) void {
    const beg = get_start_of_line(ihdr, line) + 1;
    const bpp = ihdr.get_bits_per_pixel();
    var pos = beg;
    var idx: u64 = line * ihdr.*.width; 

    while (pos - beg < ihdr.*.width * bpp) : (idx += 1) {
        var cur_pixel: u64 = 0;

        while (cur_pixel < bpp) {
            var prev: u16 = 0;

            if          (is_left and pos - beg >= bpp) {
                prev = @intCast(idat.*.data[pos - bpp]);
            } else if   (!is_left and line > 0) {
                prev = @intCast(idat.*.data[pos - get_line_width(ihdr) - 1]);
            }

            const curr: u16 = @intCast(idat.*.data[pos]);
            const value: u8 = @intCast((curr + prev) % 256);

            idat.*.data[pos] = value;

            pos += 1;
            cur_pixel += 1;
        }

        pos -= bpp;
        const color = idat.get_color_value(ihdr, plte, &pos);
        pixel_buffer[idx] = color;
    }
}

fn average_filter(ihdr: *IHDR, plte: *PLTE, idat: *IDAT, line: u32, pixel_buffer: []u32) void {
    const beg = get_start_of_line(ihdr, line) + 1;
    const bpp = ihdr.get_bits_per_pixel();
    var pos = beg;
    var idx: u64 = line * ihdr.*.width;

    while (pos - beg < ihdr.*.width * bpp) : (idx += 1) {
        var cur_pixel: u64 = 0;

        while (cur_pixel < bpp) {
            const left: u16 = if (pos - beg < bpp) 0 else @intCast(idat.data[pos - bpp]);
            const up: u16   = if (line       == 0) 0 
                else @intCast(idat.data[pos - get_line_width(ihdr) - 1]);

            const sum: f64 = @as(f64, @floatFromInt(left)) + @as(f64, @floatFromInt(up));
            const average: u16 = @as(u16, @intFromFloat(@floor(sum / 2.0)));
            const correct: u16 = @as(u16, idat.data[pos]) + average;

            idat.data[pos] = @intCast(correct % 256);
            pos += 1;
            cur_pixel += 1;
        }

        pos -= bpp;
        const color = idat.get_color_value(ihdr, plte, &pos);
        pixel_buffer[idx] = color;
    }
}

fn paeth_filter(ihdr: *IHDR, plte: *PLTE, idat: *IDAT, line: u32, pixel_buffer: []u32) void {
    const beg = get_start_of_line(ihdr, line) + 1;
    const bpp = ihdr.get_bits_per_pixel();
    var pos = beg;
    var idx: u64 = line * ihdr.*.width;

    while (pos - beg < ihdr.*.width * bpp) : (idx += 1) {
        var cur_pixel: u64 = 0;

        while (cur_pixel < bpp) {
            const line_width = get_line_width(ihdr) + 1;

            const a: i16 = if (pos - beg < bpp) 0 else @intCast(idat.*.data[pos - bpp]);
            const b: i16 = if (line == 0) 0 else @intCast(idat.*.data[pos - line_width]);
            const c: i16 = if (pos - beg < bpp or line == 0) 0 
                else @intCast(idat.*.data[pos - bpp - line_width]);

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

            value = ((value + idat.*.data[pos]) % 256);
            idat.*.data[pos] = @intCast(value);
            pos += 1;
            cur_pixel += 1;
        }

        pos -= bpp;
        const color = idat.get_color_value(ihdr, plte, &pos);
        pixel_buffer[idx] = color;
    }
}

pub fn extract_pixels(allocator: Allocator, raw_png: []const u8) Image {
    // NOTE: png has to have a png signature
    assert(raw_png.len >= 8 and mem.eql(u8, &png_sig, raw_png[0..8]));

    var pos: u32 = 8;
    var ihdr = IHDR.read_chunk(raw_png, &pos);
    var idat   = IDAT{ .data = undefined, .size = undefined };
    var plte   = PLTE{ .palette = undefined, .palette_size = undefined, };

    while (true) {
        const length = read(u32, raw_png, &pos);
        const chunk_type = read_slice(raw_png, &pos, 4);
        assert(length <= raw_png.len - pos);

        if          (mem.eql(u8, &png_idat, chunk_type)) {
            idat = IDAT.read_chunk(allocator, raw_png, &pos, length);
        } else if   (mem.eql(u8, &png_plte, chunk_type)) {
            plte = PLTE.read_chunk(raw_png, &pos, length);
        } else if   (mem.eql(u8, &png_iend, chunk_type)) {
            break;
        } else {
            pos += length;
        }

        const crc = read(u32, raw_png, &pos);
        _ = crc;
    }

    const pixel_buffer: []u32 = allocator.alloc(u32, ihdr.width * ihdr.height) catch |err| {
        std.debug.print("{any}\n", .{err});
        std.process.exit(1);
    };

    var line: u32 = 0;
    while (line < ihdr.height) {
        apply_filter(&ihdr, &plte, &idat, &line, pixel_buffer);
    }
    allocator.free(idat.data);

    return .{
        .width = ihdr.width,
        .height = ihdr.height,
        .pixels = pixel_buffer,
    }; 
}


