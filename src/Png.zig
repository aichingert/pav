const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;

const puff = @import("puff.zig");

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
        if (self.*.bit_depth < 8) {
            return ParseImageError.InvalidImage;
        }

        switch (self.*.color_type) {
            0 => if (!(self.*.bit_depth == 1 or self.*.bit_depth == 2 
                     or self.*.bit_depth == 4 or self.*.bit_depth == 8
                     or self.*.bit_depth == 16)) return ParseImageError.InvalidImage,
            3 => if (!(self.*.bit_depth == 1 or self.*.bit_depth == 2
                     or self.*.bit_depth == 4 or self.*.bit_depth == 8)) return ParseImageError.InvalidImage,
            2 => {
                if (!(self.*.bit_depth == 8 or self.*.bit_depth == 16)) return ParseImageError.InvalidImage;
                return self.*.bit_depth / 8 * RGB;
            },
            4, 6 => {
                if (!(self.*.bit_depth == 8 or self.*.bit_depth == 16)) return ParseImageError.InvalidImage;
                return self.*.bit_depth / 8 * RGBA;
            },
            else => {
                return ParseImageError.InvalidImage;
            }
        }
 
        return self.*.bit_depth / 8;
    }

    fn read_chunk(raw_png: []const u8, pos: *u32) !IHDR {
        const length = read(u32, raw_png, pos);
        if (length >= raw_png.len - pos.*) {
            return ParseImageError.InvalidImage;
        }

        const chunk_type = read_slice(raw_png, pos, 4);
        if (!mem.eql(u8, &png_ihdr, chunk_type)) {
            return ParseImageError.InvalidImage;
        }

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

    fn read_chunk(raw_png: []const u8, pos: *u32, len: u32) !PLTE {
        if (len % 3 != 0) {
            return ParseImageError.InvalidImage;
        }

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

    fn get_color_value(self: *IDAT, ihdr: *IHDR, plte: *PLTE, pos: *usize) !u32 {
        switch (ihdr.*.color_type) {
            0, 4 => return ParseImageError.InvalidImage,
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

    fn read_chunk(allocator: Allocator, ihdr: *IHDR, raw_png: []const u8, pos: *u32, length: u32) !IDAT {
        const cmf = read(u8, raw_png, pos);
        const flg = read(u8, raw_png, pos);

        const compression_method = cmf & 0x0F;
        const compression_info   = cmf >> 4;

        // NOTE: RFC - 1950 "CM = 8 denotes the "deflate" 
        // compression method ... used by gzip and PNG"
        if (compression_method != 8 or compression_info >= 8) {
            return ParseImageError.InvalidImage;
        }
        const window_size = @as(u32, 1) << @intCast(compression_info + 8);
        _   = window_size;

        const f_dict  = (flg >> 5) & 1;
        const f_level = (flg >> 6) & 3;
        // NOTE: can be ignored since it is not needed for decompression
        _ = f_level; 

        // TODO: support preset dictionarys
        if (f_dict != 0 or (@as(u32, cmf) * 256 + flg) % 31 != 0) {
            return ParseImageError.InvalidImage;
        }

        // TODO: figure the infalte more out from there

        const src = pos.*;
        var ilen: u32 = length - 2;
        var in_size: u32 = ilen;
        pos.* += ilen;
        var crc = read(u32, raw_png, pos);

        while (true) {
            const new_len = read(u32, raw_png, pos);
            const ch_type = read_slice(raw_png, pos, 4);

            if (!mem.eql(u8, &png_idat, ch_type)) {
                break;
            }

            pos.* += new_len;
            in_size += new_len;

            crc = read(u32, raw_png, pos);
        }

        const in = try allocator.alloc(u8, in_size);
        defer allocator.free(in);
        const out = try allocator.alloc(u8, 4 * ihdr.width * ihdr.height);

        pos.* = src;
        ilen = length - 2;
        var at: u32 = 0;

        while (true) {
            var i: u32 = 0;
            while (i < ilen) : (i += 1) {
                in[at] = read(u8, raw_png, pos);
                at += 1;
            }

            crc = read(u32, raw_png, pos);

            const new_len = read(u32, raw_png, pos);
            const ch_type = read_slice(raw_png, pos, 4);

            if (!mem.eql(u8, &png_idat, ch_type)) {
                pos.* -= 12;
                break;
            }

            ilen = new_len;
        }

        var s = puff.DeflateState{
            .out = out,
            .outlen = out.len,
            .outcnt = 0,
            .in = in,
            .inlen = in.len,
            .incnt = 0,
            .bitbuf = 0,
            .bitcnt = 0,
        };

        while (s.incnt <= s.inlen - 4) {
            s.puff() catch |err| {
                if (s.incnt < s.inlen - 4) {
                    return err;
                }
            };
        }

        return IDAT {
            .size = s.outcnt,
            .data = out,
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

pub fn read_image(allocator: Allocator, raw_png: []const u8) !Image {
    // NOTE: png has to have a png signature
    if (raw_png.len < 8 or !mem.eql(u8, &png_sig, raw_png[0..8])) {
        return ParseImageError.InvalidImage;
    }

    var pos: u32 = 8;
    var ihdr     = try IHDR.read_chunk(raw_png, &pos);
    var idat     = IDAT{ .data = undefined, .size = undefined };
    var plte     = PLTE{ .palette = undefined, .palette_size = undefined, };
    defer allocator.free(idat.data);

    while (true) {
        const length = read(u32, raw_png, &pos);
        const chunk_type = read_slice(raw_png, &pos, 4);

        if (length > raw_png.len - pos) {
            return ParseImageError.InvalidImage;
        }

        if          (mem.eql(u8, &png_idat, chunk_type)) {
            idat = try IDAT.read_chunk(allocator, &ihdr, raw_png, &pos, length);
        } else if   (mem.eql(u8, &png_plte, chunk_type)) {
            plte = try PLTE.read_chunk(raw_png, &pos, length);
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

    return .{
        .width = ihdr.width,
        .height = ihdr.height,
        .pixels = pixel_buffer,
    }; 
}

pub fn write_image(allocator: Allocator, path: []const u8, image: *Image) !void {
    _ = image;
    _ = allocator;

    const file = try std.fs.cwd().createFile(path, .{ .read = true });
    defer file.close();
}

