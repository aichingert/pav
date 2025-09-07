const std = @import("std");
const z   = @cImport(
    @cInclude("zlib.h")
);
const Ppm = @import("Ppm.zig");

const mem = std.mem;
const assert = std.debug.assert;
const Allocator = mem.Allocator;

const png_sig   = [_]u8{137, 80, 78, 71, 13, 10, 26, 10};
const png_ihdr  = [_]u8{'I', 'H', 'D', 'R'};
const png_plte  = [_]u8{'P', 'L', 'T', 'E'};
const png_idat  = [_]u8{'I', 'D', 'A', 'T'};
const png_iend  = [_]u8{'I', 'E', 'N', 'D'};

// TODO: a compiler macro should do this but I can't get them to work
fn read(comptime T: type, raw_png: []const u8, pos: *u32) T {
    const len: T = @bitSizeOf(T) / 8;
    const byt: T = 8;
    var value: T = 0;

    var i: T = 0;
    while (i < len) {
        value |= @as(T, raw_png[pos.* + i]) << @intCast((byt * (len - i - 1)));
        i += 1;
    }

    //const val = mem.nativeTo(u32, mem.readPackedIntNative(T, raw_png, pos.*), .little);
    pos.* += len;
    return value;
}

fn read_slice(raw_png: []const u8, pos: *u32, len: u32) []const u8 {
    const sliced = raw_png[pos.*..pos.* + len];
    pos.* += len;
    return sliced;
}

const IHDR = struct {
    width: u32,
    height: u32,

    bit_depth: u8,
    color_type: u8,
    compression_method: u8,
    filter_method: u8,
    interlace_method: u8,

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

    fn read_chunk(allocator: Allocator, raw_png: []const u8, pos: *u32, length: u32) IDAT {
        const size = 64 * 1024 * 1024;
        const buff = allocator.alloc(u8, size) catch |err| { 
            std.debug.print("ERROR: allocationg `{any}`\n", .{err}); 
            std.process.exit(1);
        };

        var idat = IDAT{
            .data = buff,
            .size = 0,
        };
        var infstream = z.z_stream{
            .avail_in = length,
            .next_in = @constCast(raw_png[pos.*..pos.* + length]).ptr,
            .avail_out = size,
            .next_out = buff.ptr,
        };

        const init_res = z.inflateInit(&infstream);
        assert(init_res == z.Z_OK);
        var infl_res = z.inflate(&infstream, z.Z_NO_FLUSH);

        if (infl_res != z.Z_STREAM_END) {
            pos.* += length;
            var crc = read(u32, raw_png, pos);

            while (true) {
                const len = read(u32, raw_png, pos);
                assert(len < raw_png.len - pos.*);
                pos.* += 4;

                infstream.avail_in = len;
                infstream.next_in = @constCast(raw_png[pos.*..pos.* + length]).ptr;
                infl_res = z.inflate(&infstream, z.Z_NO_FLUSH);

                if (infl_res == z.Z_STREAM_END) {
                    pos.* -= 8;
                    idat.size = infstream.total_out;
                    idat.data = buff;
                    return idat;
                }

                pos.* += len;
                crc = read(u32, raw_png, pos);
            }

            return idat;
        }

        assert(infl_res == z.Z_STREAM_END);
        const iend_res = z.inflateEnd(&infstream);
        assert(iend_res == z.Z_OK);

        pos.* += length;
        idat.size = infstream.total_out;
        return idat;
    }
};

pub fn extract_pixels(allocator: Allocator, raw_png: []const u8) void {
    // NOTE: png has to have a png signature
    assert(raw_png.len >= 8 and mem.eql(u8, &png_sig, raw_png[0..8]));

    var pos: u32 = 8;
    const ihdr = IHDR.read_chunk(raw_png, &pos);
    var idat   = IDAT{ .data = undefined, .size = undefined };
    var plte   = PLTE{ .palette = undefined, .palette_size = undefined, };

    while (true) {
        const length = read(u32, raw_png, &pos);
        const chunk_type = read_slice(raw_png, &pos, 4);
        std.debug.print("{any}\n", .{pos});
        assert(length < raw_png.len - pos);

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
 

    Ppm.write_png(allocator, ihdr.width, ihdr.height, plte, idat) catch |err| {
        std.debug.print("{any}\n", .{err});
    };
    allocator.free(idat.data);

    //std.debug.print("{x}\n", .{raw_png[pos..pos + 4]});
    //

    //const plte = PLTE.read_chunk(raw_png, &pos, length);
    //_ = plte;

    //length = read(u32, raw_png, &pos);
    //assert(length < raw_png.len - pos);
    //chunk_type = read_slice(raw_png, &pos, 4);

    //std.debug.print("{any}: {s}\n", .{length, chunk_type});

}


