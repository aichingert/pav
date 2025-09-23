const std = @import("std");
const mem = std.mem;
const assert = std.debug.assert;

const Png = @import("Png.zig");
const Ppm = @import("Ppm.zig");
const Webp = @import("Webp.zig");

const v = @import("voronoi.zig");
const Method = @import("utils.zig").Method;
const VkVoronoi = @import("VkVoronoi.zig");
const ComputeContext = @import("ComputeContext.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    const allocator = gpa.allocator();
    defer {
        const deinit_status = gpa.deinit();
        if (deinit_status == .leak) {
            std.debug.print("LEAKING\n", .{});
        }
    }

    var args = try std.process.ArgIterator.initWithAllocator(allocator);
    assert(args.skip());

    var paths: std.ArrayList([]const u8) = .{};
    defer paths.deinit(allocator);

    var method: Method = .random;
    var methodStr: ?[]const u8 = null;

    while (args.next()) |arg| {
        if          (arg.len > 9 and mem.eql(u8, arg[0..9], "--method=")) {
            methodStr = arg[9..];
        } else {
            try paths.append(allocator, arg);
        }
    }

    if (methodStr != null) {
        if (std.meta.stringToEnum(Method, methodStr.?)) |m| {
            method = m;
        } else {
            std.debug.print("Error: invalid method=`{s}`\n", .{methodStr.?});
            std.process.exit(1);
        }
    }

    var ctx = try ComputeContext.init(allocator);
    var vkv = try VkVoronoi.init(&ctx);
    defer ctx.deinit(allocator);
    defer vkv.deinit();

    for (paths.items) |path| {
        const file = try std.fs.cwd().openFile(path, .{});
        defer file.close();

        const file_size = try file.getEndPos();
        const raw_data = try allocator.alloc(u8, file_size);
        var reader = std.fs.File.Reader.init(file, raw_data);
        const read_len = try reader.read(raw_data);

        const out_img = try mem.concat(allocator, u8, &[_][]const u8{std.fs.path.stem(path), ".ppm"});
        var fre_out = false;
        var out_pth = out_img;

        if (std.fs.path.dirname(path)) |dir| {
            fre_out = true;
            out_pth = try std.fs.path.join(allocator, &[_][]const u8{dir, out_img});
        }

        std.debug.print("[INFO] processing=`{s}` size=`{d}kb`\n", .{path, read_len / 1000});
        var image = Png.extract_pixels(allocator, raw_data);

        std.debug.print("start\n", .{});
        try vkv.upload_image(&image);
        try vkv.compute(&image, method);
        std.debug.print("end\n", .{});

        //try v.apply(allocator, &image, method);
        try Ppm.write_image(allocator, out_pth, &image);

        allocator.free(out_img);
        if (fre_out) allocator.free(out_pth);
        allocator.free(image.pixels);
        allocator.free(raw_data);
    }
}


