const std = @import("std");

pub const Png = @import("Png.zig");
pub const Webp = @import("Webp.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    const allocator = gpa.allocator();
    defer {
        const deinit_status = gpa.deinit();
        if (deinit_status == .leak) {
            std.debug.print("LEAKING\n", .{});
        }
    }

    //const file = try std.fs.cwd().openFile("../computer-sub.png", .{});
    //const file = try std.fs.cwd().openFile("../omni-man.png", .{});
    //const file = try std.fs.cwd().openFile("../image.png", .{});
    //const file = try std.fs.cwd().openFile("../image-white.png", .{});
    //const file = try std.fs.cwd().openFile("../8_bit.png", .{});
    const file = try std.fs.cwd().openFile("../schopfhirsch.webp", .{});
            
    defer file.close();

    const file_size = try file.getEndPos();
    const raw_data = try allocator.alloc(u8, file_size);
    var reader = std.fs.File.Reader.init(file, raw_data);
    const read_len = try reader.read(raw_data);

    std.debug.print("FILE_SIZE: {any} \\ READ_LEN: {any}\n", .{file_size, read_len});
    Webp.extract_pixels(allocator, raw_data);
    allocator.free(raw_data);
}


