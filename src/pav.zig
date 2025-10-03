// TODO: start with frontend 
// to know which calls will
// be needed
// TODO: implement wasm api 
// TODO: implement own inflate
// since I can't build c for
// wasm idk - maybe i can 
// we will see

const std = @import("std");
const wasm_allocator = std.heap.wasm_allocator;


extern fn console_log(buf: usize, len: usize) void;

export fn parse_image(name: [*]u8, name_len: usize, raw: [*]u8) void {
    _ = raw;

    console_log(@intFromPtr(name), name_len);
}

export fn add(a: u32, b: u32) u32 {
    return a + b;
}


