// TODO: start with frontend 
// to know which calls will
// be needed
// TODO: implement wasm api 
// TODO: implement own inflate
// since I can't build c for
// wasm idk - maybe i can 
// we will see

//extern fn console_log(a: []const u8) void;
//
//export fn parse_image(name: []const u8, raw: []u8) void {
//    _ = raw;
//    console_log(name);
//}

export fn add(a: u32, b: u32) u32 {
    return a + b;
}

