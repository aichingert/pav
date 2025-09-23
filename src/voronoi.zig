const std = @import("std");

const vk = @import("vulkan");

const utils = @import("utils.zig");
const Image = utils.Image;
const Method = utils.Method;

const assert = std.debug.assert;
const mem = std.mem;
const Allocator = mem.Allocator;

const Point = struct {
    x: u32,
    y: u32,

    fn less_than(context: void, a: Point, b: Point) bool {
        _ = context;

        if (a.y == b.y) {
            return a.x < b.x;
        }

        return a.y < b.y;
    }
};

fn place_points_random(width: u32, height: u32, points: []Point) void {
    const random = std.crypto.random;

    // TODO: better random numbers - no duplicates
    for (points) |* point| {
        const x = random.intRangeAtMost(u32, 0, width - 1);
        const y = random.intRangeAtMost(u32, 0, height - 1);
        point.*.x = x;
        point.*.y = y;
    }
}

fn euclidean_distance(x: u32, y: u32, x1: u32, y1: u32) f64 {
    const xf: f64 = @as(f64, @floatFromInt(x));
    const yf: f64 = @as(f64, @floatFromInt(y));
    const x1f: f64 = @as(f64, @floatFromInt(x1));
    const y1f: f64 = @as(f64, @floatFromInt(y1));
    return @sqrt((xf - x1f) * (xf - x1f) + (yf - y1f) * (yf - y1f));
}

pub fn apply(allocator: Allocator, image: *Image, method: Method) !void {
    const total_points: f64 = @floatFromInt(image.*.width * image.*.height);
    const points_to_place: u32 = @intFromFloat(total_points * 0.01);
    const points = try allocator.alloc(Point, points_to_place);
    defer allocator.free(points);

    switch (method) {
        .random => place_points_random(image.*.width, image.*.height, points),
    }
    std.mem.sort(Point, points[0..], {}, Point.less_than);

    var cnt: u64 = 0;

    var i: u32 = 0;
    while (i < image.*.height) {
        std.debug.print("{any}\n", .{i});
        var j: u32 = 0;

        while (j < image.*.width) {
            var k: u32 = 1;
            var closest: Point = points[0];
            var cur_dis = euclidean_distance(closest.x, closest.y, j, i);

            while (k < points.len) {
                const pnt_dis = euclidean_distance(points[k].x, points[k].y, j, i);

                if (pnt_dis <= cur_dis) {
                    cur_dis = pnt_dis;
                    closest = points[k];
                }

                k += 1;
                cnt += 1;
            }

            const dst_idx = i * image.*.width + j;
            const src_idx = closest.y * image.*.width + closest.x;
            image.pixels[dst_idx] = image.pixels[src_idx];
            j += 1;
        }

        i += 1;
    }
}
