// TODO: figure out how to work with errors when communicating with wasm

const std = @import("std");
const assert = std.debug.assert;
const wasm_allocator = std.heap.wasm_allocator;

const utils = @import("utils.zig");
const Image = utils.Image;
const ImageType = utils.ImageType;
const ParseImageError = utils.ParseImageError;

const Png = @import("Png.zig");

pub extern fn debug_log(ptr: [*]u8, len: usize) void;

const WasmArray = struct {
    ptr: [*]u8,
    len: usize,

    export fn init(ptr: [*]u8, len: usize) *WasmArray {
        const arr = wasm_allocator.create(WasmArray) catch unreachable;
        arr.ptr = ptr;
        arr.len = len;
        return arr;
    }
};

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
            const png_img = Png.extract_pixels(wasm_allocator, raw_data) catch unreachable;
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

