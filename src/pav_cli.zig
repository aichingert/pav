const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;
const assert = std.debug.assert;

const Png = @import("Png.zig");
const Ppm = @import("Ppm.zig");
const Webp = @import("Webp.zig");

const v = @import("voronoi.zig");
const utils = @import("utils.zig");
const Image = utils.Image;
const Method = utils.Method;
const ImageType = utils.ImageType;
const VoronoiConfig = utils.VoronoiConfig;

// NOTE: used because wasm does not have true "randomness"
// at least what I found therefore call to js using rand
// native implements this function itself
pub export fn rand() usize {
    const random = std.crypto.random;
    return random.intRangeAtMost(usize, 0, 2 << 30);
}

fn is_argument(arg: [:0]u8, s: []const u8) bool {
    return arg.len > s.len and mem.eql(u8, arg[0..s.len], s);
}

fn process(
    allocator: Allocator, 
    in_path: []const u8, 
    out_path: []const u8,
    config: VoronoiConfig,
) !void {
    const file_ext: []const u8 = std.fs.path.extension(in_path);
    if (file_ext.len <= 0) {
        std.debug.print(
            "[INFO]: missing file extension: skipping `{s}`\n", 
            .{in_path});
        return;
    }

    const ext = std.meta.stringToEnum(ImageType, file_ext[1..]) orelse {
        std.debug.print(
            "[INFO]: unsupported file extension: skipping `{s}`\n", 
            .{file_ext});
        return;
    };

    const file = try std.fs.cwd().openFile(in_path, .{});
    defer file.close();

    const file_size = try file.getEndPos();
    const raw_data = try allocator.alloc(u8, file_size);
    defer allocator.free(raw_data);

    var reader = std.fs.File.Reader.init(file, raw_data);
    const read_len = try reader.read(raw_data);
    var image: Image = undefined;

    std.debug.print("[INFO] processing=`{s}` size=`{d}kb`\n", .{in_path, read_len / 1000}); 

    switch (ext) {
        .png => image = try Png.extract_pixels(allocator, raw_data),
        .jpg => {
            std.debug.print("[INFO]: not yet supported jpg: skipping\n", .{});
            return;
        },
        .webp => {
            std.debug.print("[INFO]: not yet supported webp: skipping\n", .{});
            return;
        },
    }
    defer allocator.free(image.pixels);
    try v.apply(allocator, &image, config);

    // TODO: check output as well
    try Ppm.write_image(allocator, out_path, &image);
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    const allocator = gpa.allocator();
    defer { _ = gpa.deinit(); }

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var i: u32 = 1;
    var config = VoronoiConfig{
        .init = .random,
        .seeds = 0,
    };

    while (i < args.len) : (i += 1) {
        if          (is_argument(args[i], "--method=")) {
            config.init = std.meta.stringToEnum(Method, args[i][9..]) orelse {
                std.debug.print("Error: invalid method=`{s}`\n", .{args[i][9..]});
                std.process.exit(1);
            };
        } else if   (is_argument(args[i], "--seeds=")) {
            config.seeds = try std.fmt.parseInt(u32, args[i][8..], 10);
        } else {
            if (i + 1 < args.len and is_argument(args[i + 1], "--out=")) {
                const out_path = args[i + 1][6..];
                try process(allocator, args[i], out_path, config);
                i += 1;
            } else {
                const dir_name = std.fs.path.dirname(args[i]) orelse ".";
                const to_concat = [_][]const u8{dir_name, "/out_", std.fs.path.basename(args[i])};
                const out_path = try mem.concat(allocator, u8, &to_concat);
                defer allocator.free(out_path);
                try process(allocator, args[i], out_path, config);
            }
        }
    }
}

