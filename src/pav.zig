// TODO: start with frontend 
// to know which calls will
// be needed
// TODO: implement wasm api 
// TODO: implement own inflate
// since I can't build c for
// wasm idk - maybe i can 
// we will see

extern fn console_log(a: [*]u8) void;

export fn parse_image(name: [*]u8, raw: [*]u8) u8 {
    _ = raw;
    return name[0];
}

export fn add(a: u32, b: u32) u32 {
    return a + b;
}


