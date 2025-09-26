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

    var in_paths: std.ArrayList([]const u8) = .{};
    var out_paths: std.ArrayList([]const u8) = .{};
    defer in_paths.deinit(allocator);
    defer out_paths.deinit(allocator);

    var method: Method = .random;
    var has_in: bool = false;
    var methodStr: ?[]const u8 = null;

    while (args.next()) |arg| {
        if          (arg.len > 9 and mem.eql(u8, arg[0..9], "--method=")) {
            methodStr = arg[9..];
        } else if   (arg.len > 3 and mem.eql(u8, arg[0..3], "-o=")) {
            if (has_in) {
                const out_path = try allocator.dupe(u8, arg[3..]);
                try out_paths.append(allocator, out_path);
                has_in = false;
            } else {
                std.debug.print("ERROR: missing input for output specifier\n", .{});
                return;
            }
        } else {
            if (has_in) {
                const dirname = 
                    if (std.fs.path.dirname(arg)) |dir| 
                        dir 
                    else
                        ".";

                const img_out_path = try mem.concat(
                    allocator, 
                    u8, 
                    &[_][]const u8{dirname, "/out_", std.fs.path.basename(arg)});
                try out_paths.append(allocator, img_out_path);
            }

            has_in = true;
            try in_paths.append(allocator, arg);
        }
    }

    if (has_in) {
        const path = in_paths.items[in_paths.items.len - 1];
        const dirname =
            if (std.fs.path.dirname(path)) |dir| 
                dir 
            else
                ".";

        const img_out_path = try mem.concat(
            allocator, 
            u8, 
            &[_][]const u8{dirname, "/out_", std.fs.path.basename(path)});
        try out_paths.append(allocator, img_out_path);
    }

    assert(in_paths.items.len == out_paths.items.len);

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

    for (0..in_paths.items.len) |i| {
        const file = try std.fs.cwd().openFile(in_paths.items[i], .{});
        defer file.close();

        const file_size = try file.getEndPos();
        const raw_data = try allocator.alloc(u8, file_size);
        var reader = std.fs.File.Reader.init(file, raw_data);
        const read_len = try reader.read(raw_data);

        std.debug.print("[INFO] processing=`{s}` size=`{d}kb`\n", .{in_paths.items[i], read_len / 1000});

        var image = Png.extract_pixels(allocator, raw_data);
        try vkv.compute(&image, method);

        //try v.apply(allocator, &image, method);
        try Ppm.write_image(allocator, out_paths.items[i], &image);

        allocator.free(image.pixels);
        allocator.free(raw_data);
        allocator.free(out_paths.items[i]);
    }

    vkv.deinit();
    ctx.deinit(allocator);
}


