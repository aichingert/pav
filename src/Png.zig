const std = @import("std");

extern fn console_log(arg: []const u8) void;

export fn extract_pixels_from_png(path: []const u8) void {
    console_log(path);
}


