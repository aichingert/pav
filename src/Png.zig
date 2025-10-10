const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;
const assert = std.debug.assert;

const utils = @import("utils.zig");
const read = utils.read;
const read_slice = utils.read_slice;
const Image = utils.Image;
const ParseImageError = utils.ParseImageError;

const RGB = utils.RGB;
const RGBA = utils.RGBA;

const png_sig   = [_]u8{137, 80, 78, 71, 13, 10, 26, 10};
const png_ihdr  = [_]u8{'I', 'H', 'D', 'R'};
const png_plte  = [_]u8{'P', 'L', 'T', 'E'};
const png_idat  = [_]u8{'I', 'D', 'A', 'T'};
const png_iend  = [_]u8{'I', 'E', 'N', 'D'};

const zlib_maxbits: u32 = 15;
const zlib_maxlcodes: u32 = 15;
const zlib_maxdcodes: u32 = 286;
const zlib_maxcodes: u32 = (zlib_maxlcodes + zlib_maxdcodes);
const zlib_fixlcodes: u32 = 288;

pub const IHDR = struct {
    width: u32,
    height: u32,

    bit_depth: u8,
    color_type: u8,
    compression_method: u8,
    filter_method: u8,
    interlace_method: u8,

    fn get_bits_per_pixel(self: *IHDR) !u8 {
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
                return ParseImageError.InvalidImage;
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
    size: usize,

    const Huffman = struct {
        count: []u16,
        symbl: []u16,
    };

    fn get_color_value(self: *IDAT, ihdr: *IHDR, plte: *PLTE, pos: *usize) !u32 {
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
                return ParseImageError.InvalidImage;
            }
        }

        return 0;
    }

    fn read_bits(bitbuf: *u32, bitcnt: *u32, raw_png: []const u8, pos: *u32, need: u32) u32 {
        // TODO: len checks

        var val = bitbuf.*;

        while (bitcnt.* < need) {
            val |= @as(u32, raw_png[@intCast(pos.*)]) << @intCast(bitcnt.*);
            bitcnt.* += 8;
        }

        bitbuf.* = val >> @intCast(need);
        bitcnt.* -= need;
        return val & ((@as(u32, 1) << @intCast(need)) - 1);
    }

    fn construct(h: *Huffman, length: []u16, n: u32) u32 {
        for (0..zlib_maxbits + 1)  |i| {
            h.count[i] = 0;
        }
        for (0..n) |i| {
            h.count[length[i]] += 1;
        }

        if (h.count[0] == n) {
            return 0;
        }

        var left: i32 = 1;
        for (1..zlib_maxbits + 1) |i| {
            left = left << 1;
            left -= @intCast(h.count[i]);

            assert(left >= 0);
        }

        var offs: [zlib_maxbits + 1]u16 = undefined;
        offs[1] = 0;

        for (1..zlib_maxbits) |i| {
            offs[i + 1] = offs[i] + h.count[i];
        }

        for (0..n) |i| {
            if (length[i] != 0) {
                h.symbl[offs[length[i]]] = @intCast(i);
                offs[length[i]] += 1;
            }
        }

        std.debug.print("{any}\n", .{left});
        return @intCast(left);
    }

    fn decode(bitbuf: *u32, bitcnt: *u32, raw_png: []const u8, pos: *u32, h: *Huffman) u32 {
        var code: i32 = 0;
        var first: i32 = 0;
        var index: i32 = 0;

        for (1..zlib_maxbits + 1) |i| {
            code |= @intCast(IDAT.read_bits(bitbuf, bitcnt, raw_png, pos, 1));
            const count = @as(i32, h.count[i]);

            if (code - count > first) {
                return @as(u32, h.symbl[@intCast(index + (code - first))]);
            }

            index += count;
            first += count;
            first = first << 1;
            code = code << 1;
        }

        assert(false);
        return 0;
    }

    fn dynamic(bitbuf: *u32, bitcnt: *u32, raw_png: []const u8, pos: *u32) u32 {
        var lengths: [zlib_maxcodes]u16 = undefined;
        // TODO: fix undefined
        var lencode_count: [zlib_maxbits + 1]u16 = undefined;
        var lencode_symbl: [zlib_maxlcodes]u16 = undefined;
        var discode_count: [zlib_maxbits + 1]u16 = undefined;
        var discode_symbl: [zlib_maxlcodes]u16 = undefined;

        var lencode = Huffman{
            .count = &lencode_count,
            .symbl = &lencode_symbl,
        };
        var discode = Huffman{
            .count = &discode_count,
            .symbl = &discode_symbl,
        };
        discode.count[0] = 0;
        const order = [_]u16{16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15};

        const nlen = IDAT.read_bits(bitbuf, bitcnt, raw_png, pos, 5) + 257;
        const ndis = IDAT.read_bits(bitbuf, bitcnt, raw_png, pos, 5) + 1;
        const ncod = IDAT.read_bits(bitbuf, bitcnt, raw_png, pos, 4) + 4;

        std.debug.print("{any} - {any} - {any}\n", .{nlen, ndis, ncod});

        for (0..ncod) |i| {
            lengths[order[i]] = @intCast(IDAT.read_bits(bitbuf, bitcnt, raw_png, pos, 3));
        }
        for (ncod..19) |i| {
            lengths[order[i]] = 0;
        }

        const err = construct(&lencode, &lengths, 19);
        std.debug.print(".{any}\n", .{err});
        assert(err == 0);

        var index: u32 = 0;
        while (index < nlen + ndis) {
            var symbol = decode(bitbuf, bitcnt, raw_png, pos, &lencode);

            if (symbol < 16) {
                lengths[index] = @intCast(symbol);
                index += 1;
            } else {
                var len: u16 = 0;

                if (symbol == 16) {
                    assert(index > 0);
                    len = lengths[index - 1];
                    symbol = 3 + IDAT.read_bits(bitbuf, bitcnt, raw_png, pos, 2);
                } else if (symbol == 17) {
                    symbol = 3 + IDAT.read_bits(bitbuf, bitcnt, raw_png, pos, 3);
                } else {
                    symbol = 11 + IDAT.read_bits(bitbuf, bitcnt, raw_png, pos, 7);
                }

                assert(index + symbol <= nlen + ndis);
                while (symbol > 0) {
                    lengths[index] = len;
                    index += 1;
                    symbol -= 1;
                }
            }
        }

        assert(lengths[256] == 0);

        return 0;
    }

    fn read_chunk(allocator: Allocator, raw_png: []const u8, pos: *u32, length: u32) IDAT {
        _ = allocator;

        const cmf = read(u8, raw_png, pos);
        const flg = read(u8, raw_png, pos);

        const compression_method = cmf & 0x0F;
        const compression_info   = cmf >> 4;

        // NOTE: RFC - 1950 "CM = 8 denotes the "deflate" 
        // compression method ... used by gzip and PNG"
        assert(compression_method == 8 and compression_info < 8);
        const window_size = @as(u32, 1) << @intCast(compression_info + 8);
        _   = window_size;

        const f_dict  = (flg >> 5) & 1;
        const f_level = (flg >> 6) & 3;
        // NOTE: can be ignored since it is not needed for decompression
        _ = f_level; 

        // TODO: support preset dictionarys
        assert(f_dict == 0 and (@as(u32, cmf) * 256 + flg) % 31 == 0);

        // TODO: figure the infalte more out from there

        _ = length;

        var bitcnt: u32 = 0;
        var bitbuf: u32 = 0;
        
        while (true) {
            const blast = IDAT.read_bits(&bitbuf, &bitcnt, raw_png, pos, 1);
            const ctype = IDAT.read_bits(&bitbuf, &bitcnt, raw_png, pos, 2);

            std.debug.print("{any} - {any}\n", .{blast, ctype});
            if (ctype == 2) {
                var res = dynamic(&bitbuf, &bitcnt, raw_png, pos);
                res = 0;
            }

            if (blast == 1) {
                break;
            }
        }

        return IDAT {
            .size = 0,
            .data = undefined,
        };
    }
};

fn get_filter_type(idat: *IDAT, ihdr: *IHDR, line: u32) !u8 {
    return idat.data[try get_start_of_line(ihdr, line)];
}

fn get_line_width(ihdr: *IHDR) !usize {
    return @as(usize, ihdr.*.width) * @as(usize, try ihdr.get_bits_per_pixel());
}

fn get_start_of_line(ihdr: *IHDR, line: u32) !usize {
    return @as(usize, line) * try get_line_width(ihdr) + @as(usize, line);
}

fn apply_filter(ihdr: *IHDR, plte: *PLTE, idat: *IDAT, line: *u32, pixel_buffer: []u32) !void {
    const filter: u8 = try get_filter_type(idat, ihdr, line.*);

    switch (filter) {
        0 => try copy_scanline(ihdr, plte, idat, line.*, pixel_buffer),
        1 => try subtract_filter(ihdr, plte, idat, line.*, true, pixel_buffer),
        2 => try subtract_filter(ihdr, plte, idat, line.*, false, pixel_buffer),
        3 => try average_filter(ihdr, plte, idat, line.*, pixel_buffer),
        4 => try paeth_filter(ihdr, plte, idat, line.*, pixel_buffer),
        else => {
            return ParseImageError.InvalidImage;
        }
    }

    line.* += 1;
}

fn copy_scanline(ihdr: *IHDR, plte: *PLTE, idat: *IDAT, line: u32, pixel_buffer: []u32) !void {
    const beg = try get_start_of_line(ihdr, line) + 1;
    const bpp = try ihdr.get_bits_per_pixel();
    var pos = beg;
    var idx: usize = line * ihdr.*.width;

    while (pos - beg < ihdr.*.width * bpp) : (idx += 1) {
        const color = try idat.get_color_value(ihdr, plte, &pos);
        pixel_buffer[idx] = color;
    }
}

// NOTE: there are two subtract filters (left and up)
fn subtract_filter(ihdr: *IHDR, plte: *PLTE, idat: *IDAT, line: u32, is_left: bool, pixel_buffer: []u32) !void {
    const beg = try get_start_of_line(ihdr, line) + 1;
    const bpp = try ihdr.get_bits_per_pixel();
    var pos = beg;
    var idx: usize = line * ihdr.*.width; 

    while (pos - beg < ihdr.*.width * bpp) : (idx += 1) {
        var cur_pixel: usize = 0;

        while (cur_pixel < bpp) {
            var prev: u16 = 0;

            if          (is_left and pos - beg >= bpp) {
                prev = @intCast(idat.*.data[pos - bpp]);
            } else if   (!is_left and line > 0) {
                prev = @intCast(idat.*.data[pos - try get_line_width(ihdr) - 1]);
            }

            const curr: u16 = @intCast(idat.*.data[pos]);
            const value: u8 = @intCast((curr + prev) % 256);

            idat.*.data[pos] = value;

            pos += 1;
            cur_pixel += 1;
        }

        pos -= bpp;
        const color = try idat.get_color_value(ihdr, plte, &pos);
        pixel_buffer[idx] = color;
    }
}

fn average_filter(ihdr: *IHDR, plte: *PLTE, idat: *IDAT, line: u32, pixel_buffer: []u32) !void {
    const beg = try get_start_of_line(ihdr, line) + 1;
    const bpp = try ihdr.get_bits_per_pixel();
    var pos = beg;
    var idx: usize = line * ihdr.*.width;

    while (pos - beg < ihdr.*.width * bpp) : (idx += 1) {
        var cur_pixel: usize = 0;

        while (cur_pixel < bpp) {
            const left: u16 = if (pos - beg < bpp) 0 else @intCast(idat.data[pos - bpp]);
            const up: u16   = if (line       == 0) 0 
                else @intCast(idat.data[pos - try get_line_width(ihdr) - 1]);

            const sum: f64 = @as(f64, @floatFromInt(left)) + @as(f64, @floatFromInt(up));
            const average: u16 = @as(u16, @intFromFloat(@floor(sum / 2.0)));
            const correct: u16 = @as(u16, idat.data[pos]) + average;

            idat.data[pos] = @intCast(correct % 256);
            pos += 1;
            cur_pixel += 1;
        }

        pos -= bpp;
        const color = try idat.get_color_value(ihdr, plte, &pos);
        pixel_buffer[idx] = color;
    }
}

fn paeth_filter(ihdr: *IHDR, plte: *PLTE, idat: *IDAT, line: u32, pixel_buffer: []u32) !void {
    const beg = try get_start_of_line(ihdr, line) + 1;
    const bpp = try ihdr.get_bits_per_pixel();
    var pos = beg;
    var idx: usize = line * ihdr.*.width;

    while (pos - beg < ihdr.*.width * bpp) : (idx += 1) {
        var cur_pixel: usize = 0;

        while (cur_pixel < bpp) {
            const line_width = try get_line_width(ihdr) + 1;

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
        const color = try idat.get_color_value(ihdr, plte, &pos);
        pixel_buffer[idx] = color;
    }
}

pub fn extract_pixels(allocator: Allocator, raw_png: []const u8) !Image {
    // NOTE: png has to have a png signature
    assert(raw_png.len >= 8 and mem.eql(u8, &png_sig, raw_png[0..8]));

    var pos: u32 = 8;
    var ihdr     = IHDR.read_chunk(raw_png, &pos);
    var idat     = IDAT{ .data = undefined, .size = undefined };
    var plte     = PLTE{ .palette = undefined, .palette_size = undefined, };

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

    if (idat.size < ihdr.width * ihdr.height) {
        return ParseImageError.InvalidImage;
    }
    const pixel_buffer: []u32 = try allocator.alloc(u32, ihdr.width * ihdr.height);

    var line: u32 = 0;
    while (line < ihdr.height) {
        try apply_filter(&ihdr, &plte, &idat, &line, pixel_buffer);
    }
    allocator.free(idat.data);

    return .{
        .width = ihdr.width,
        .height = ihdr.height,
        .pixels = pixel_buffer,
    }; 
}


