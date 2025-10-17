// TODO: start with frontend 
// to know which calls will
// be needed
// TODO: implement wasm api 
// TODO: implement own inflate
// since I can't build c for
// wasm idk - maybe i can 
// we will see

const std = @import("std");
const assert = std.debug.assert;
const wasm_allocator = std.heap.wasm_allocator;

const utils = @import("utils.zig");
const ImageType = utils.ImageType;
const ParseImageError = utils.ParseImageError;

const Png = @import("Png.zig");


pub extern fn debug_log(ptr: [*]u8, len: usize) void;

export fn alloc(len: usize) usize {
    const buf = wasm_allocator.alloc(u8, len) catch return 0;
    return @intFromPtr(buf.ptr);
}

export fn free(ptr: [*]u8, len: usize) void {
    wasm_allocator.free(ptr[0..len]);
}

export fn parse_image(
    name: [*]u8, 
    name_len: usize, 
    raw: [*]u8,
    raw_len: usize,
) usize {
    const name_str: []const u8 = name[0..name_len];
    const file_ext: []const u8 = std.fs.path.extension(name_str);

    if (file_ext.len <= 0) {
        return 3;
    }

    const ext = std.meta.stringToEnum(ImageType, file_ext[1..]) orelse {
        debug_log(@ptrCast(@constCast("hallo")), 5);
        return 1;
    };

    _ = ext;
    const raw_data: []const u8 = raw[0..raw_len];
    debug_log(@ptrCast(@constCast(raw_data)), raw_len);
    return @intCast(raw_data[1]);

    //switch (ext) {
    //    .png => {
    //        const img = Png.extract_pixels(wasm_allocator, raw_data) catch |err| {
    //            if (err == ParseImageError.ThisError) {
    //                return @intCast(raw_data[0]);
    //            }
    //            return 2;
    //        };
    //        _ = img;
    //    },
    //    .jpg => {},
    //    .webp => {},
    //}

    //debug_log(@ptrCast(@constCast(name_str)), name_str.len);
    //debug_log(@ptrCast(@constCast(file_ext)), file_ext.len);
    //debug_log(name, name_len);
    //debug_log(raw, raw_len);

    //return 0;
}

