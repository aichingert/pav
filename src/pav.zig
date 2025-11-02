// TODO: figure out how to work with errors when communicating with wasm

const std = @import("std");
const assert = std.debug.assert;
const wasm_allocator = std.heap.wasm_allocator;

const v = @import("voronoi.zig");

const utils = @import("utils.zig");
const Method = utils.Method;
const Image = utils.Image;
const ImageType = utils.ImageType;
const VoronoiConfig = utils.VoronoiConfig;
const ParseImageError = utils.ParseImageError;

const Png = @import("Png.zig");

pub extern fn debug_log(ptr: [*]u8, len: usize) void;

const WasmArray = struct {
    ptr: [*]u8,
    len: usize,
};

export fn wasm_array_init(ptr: [*]u8, len: usize) *WasmArray {
    const arr = wasm_allocator.create(WasmArray) catch unreachable;
    arr.ptr = ptr;
    arr.len = len;
    return arr;
}

export fn alloc(len: usize) usize {
    const buf = wasm_allocator.alloc(u8, len) catch return 0;
    return @intFromPtr(buf.ptr);
}

export fn free(ptr: [*]u8, len: usize) void {
    wasm_allocator.free(ptr[0..len]);
}

export fn image_get_width(img: *Image) u32 {
    return img.width;
}

export fn image_get_height(img: *Image) u32 {
    return img.height;
}

export fn image_get_pixels(img: *Image) [*]u32 {
    return @ptrCast(img.pixels);
}

export fn image_copy(img: *Image) *Image {
    var cpy = wasm_allocator.create(Image) catch unreachable;
    cpy.width = img.width;
    cpy.height = img.height;
    cpy.pixels = wasm_allocator.alloc(u32, img.pixels.len) catch unreachable;

    for (img.pixels, 0..) |pix, i| {
        cpy.pixels[i] = pix;
    }
    return cpy;
}

export fn image_free(img: *Image) void {
    wasm_allocator.free(img.pixels);
    wasm_allocator.destroy(img);
}

export fn apply_voronoi(img: *Image, init: Method, seeds: u32) void {
    v.apply(wasm_allocator, img, .{ .init = init, .seeds = seeds }) catch unreachable;
}

export fn parse_image(
    file: *WasmArray,
    data: *WasmArray,
) *Image {
    var img = wasm_allocator.create(Image) catch unreachable;
    img.width = 0;
    img.height = 0;

    const name_str: []const u8 = file.ptr[0..file.len];
    const file_ext: []const u8 = std.fs.path.extension(name_str);

    if (file_ext.len <= 0) {
        return img;
    }

    const ext = std.meta.stringToEnum(ImageType, file_ext[1..]) orelse {
        return img;
    };

    const raw_data: []const u8 = data.ptr[0..data.len];

    switch (ext) {
        .png => {
            const png_img = Png.read_image(wasm_allocator, raw_data) catch unreachable;
            img.width = png_img.width;
            img.height = png_img.height;
            img.pixels = png_img.pixels;
            return img;
        },
        .jpg => {},
        .webp => {},
    }

    return img;
}

