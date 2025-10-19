const std = @import("std");
const assert = std.debug.assert;
const mem = std.mem;
const Allocator = mem.Allocator;

const utils = @import("utils.zig");
const Image = utils.Image;
const VoronoiConfig = utils.VoronoiConfig;

const CTRL_BIT: u32 = 1 << 25;

extern fn rand() usize;

const Pixel = packed struct(u64) {
    y: u16,
    x: u16,
    color: u32,
};

pub const Queue = struct {
    buf: []Pixel,

    start: usize,
    end: usize,
    cap: usize,
    len: usize,

    pub fn init(buf: []Pixel) Queue {
        var self: Queue = undefined;

        self.buf = buf;
        self.start = 0;
        self.end = 0;
        self.len = 0;
        self.cap = buf.len;
        return self;
    }

    pub fn enqueue(self: *Queue, value: Pixel) void {
        if (self.end == self.cap) {
            assert(self.start != 0);
            self.end = 0;
        }
        assert(self.len < self.cap);
        self.buf[self.end] = value;
        self.end += 1;
        self.len += 1;
    }

    pub fn dequeue(self: *Queue) Pixel {
        if (self.start + 1 == self.cap) {
            self.start = 0;
        }

        assert(self.len > 0);
        self.len -= 1;
        self.start += 1;
        return self.buf[self.start - 1];
    }
};

fn place_points_random(
    num_points: u32, 
    queue: *Queue, 
    image: *Image,
) void {
    var xoshiro = std.Random.DefaultPrng.init(rand());
    const random = xoshiro.random();

    for (0..num_points) |_| {
        const x = random.intRangeAtMost(u16, 0, @intCast(image.width - 1));
        const y = random.intRangeAtMost(u16, 0, @intCast(image.height - 1));

        const index = @as(u32, y) * image.width + @as(u32, x);

        if (image.pixels[index] & CTRL_BIT != CTRL_BIT) {
            queue.enqueue(.{
                .x = x,
                .y = y,
                .color = image.pixels[index],
            });
            image.pixels[index] |= CTRL_BIT;
        }
    }
}

pub fn apply(allocator: Allocator, image: *Image, config: VoronoiConfig) !void {
    const buf  = try allocator.alloc(Pixel, image.pixels.len);
    var queue = Queue.init(buf);
    var conf = config;

    // NOTE: when seeds is zero means default use a sixteenth
    if (conf.seeds == 0) {
        conf.seeds = @as(u32, @intCast(image.pixels.len)) / 16;
    } else if (conf.seeds > image.pixels.len) {
        conf.seeds = @intCast(image.pixels.len);
    }

    switch (conf.init) {
        .random => place_points_random(conf.seeds, &queue, image),
    }

    const dirs = [_][3]i64{
        [_]i64{0, 1, @as(i64, image.width)},
        [_]i64{1, 0, 1}, 
        [_]i64{0, -1, -@as(i64, image.width)}, 
        [_]i64{-1, 0, -1}
    };

    while (queue.len > 0) {
        const wave_len = queue.len;

        for (0..wave_len) |_| {
            const pxl = queue.dequeue();

            for (dirs) |dir| {
                const x = @as(i64, pxl.x) + dir[0];
                const y = @as(i64, pxl.y) + dir[1];

                if (x < 0 or y < 0 or x >= @as(i64, image.width) or y >= @as(i64, image.height)) {
                    continue;
                }

                const idx: u32 = @intCast(@as(i64, pxl.y * image.width + pxl.x) + dir[2]);

                if (image.pixels[idx] & CTRL_BIT == 0) {
                    image.pixels[idx] = pxl.color | CTRL_BIT;
                    queue.enqueue(.{
                        .y = @intCast(y),
                        .x = @intCast(x),
                        .color = pxl.color,
                    });
                }
            }
        }
    }

    allocator.free(buf);
}
