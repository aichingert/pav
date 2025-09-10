const std = @import("std");

const assert = std.debug.assert;
const mem = std.mem;
const Allocator = mem.Allocator;

pub const RGB: u8 = 3;
pub const RGBA: u8 = 4;

// NOTE: currently rgb might include alpha
pub const COLOR_CHANNELS: u8 = RGB;

pub const Method = enum {
    random,
};

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
        const x = random.intRangeAtMost(u32, 0, width);
        const y = random.intRangeAtMost(u32, 0, height);
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

pub fn apply(allocator: Allocator, width: u32, height: u32, pixel_buffer: []u8, method: Method) !void {
    const total_points: f64 = @floatFromInt(width * height);
    const points_to_place: u32 = @intFromFloat(total_points * 0.001);
    const points = try allocator.alloc(Point, points_to_place);
    defer allocator.free(points);

    switch (method) {
        .random => place_points_random(width, height, points),
    }
    std.mem.sort(Point, points[0..], {}, Point.less_than);

    var cnt: u64 = 0;

    var i: u32 = 0;
    while (i < height) {
        var j: u32 = 0;

        while (j < width) {
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

            var dst_idx = i * width * COLOR_CHANNELS + j * COLOR_CHANNELS;
            var src_idx = closest.y * width * COLOR_CHANNELS + closest.x * COLOR_CHANNELS;
            var colors: u8 = 0;

            while (colors < COLOR_CHANNELS) {
                if (dst_idx < pixel_buffer.len and src_idx < pixel_buffer.len) {
                    pixel_buffer[dst_idx] = pixel_buffer[src_idx];
                }
                colors += 1;
                dst_idx += 1;
                src_idx += 1;
                cnt += 1;
            }
            j += 1;
        }

        i += 1;
    }
    std.debug.print("{any} {any} - {any} - {any}\n", .{points_to_place, pixel_buffer.len, width * height * COLOR_CHANNELS, cnt});
}
