const std = @import("std");
const assert = std.debug.assert;
const mem = std.mem;
const Allocator = mem.Allocator;

const utils = @import("utils.zig");
const Image = utils.Image;
const Method = utils.Method;

const CTRL_BIT: u32 = 1 << 25;

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
    // TODO: in wasm call to js to get a random seed
    var xoshiro = std.Random.DefaultPrng.init(248092);
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

pub fn apply(allocator: Allocator, image: *Image, method: Method) !void {
    const buf  = try allocator.alloc(Pixel, image.pixels.len);
    var queue = Queue.init(buf);

    const total_points: f32 = @floatFromInt(image.width * image.height);
    const points_to_place: u32 = @intFromFloat(total_points * 0.01);

    switch (method) {
        .random => place_points_random(points_to_place, &queue, image),
    }

    while (queue.len > 0) {
        const wave_len = queue.len;

        for (0..wave_len) |_| {
            const pxl = queue.dequeue();
            const index = pxl.y * image.width + pxl.x;

            // TODO: maybe use for loops
            if (pxl.y > 0 and image.pixels[index - image.width] & CTRL_BIT == 0)  {
                image.pixels[index - image.width] = pxl.color | CTRL_BIT;
                queue.enqueue(.{
                    .y = pxl.y - 1,
                    .x = pxl.x,
                    .color = pxl.color,
                });
            }
            if (pxl.x > 0 and image.pixels[index - 1] & CTRL_BIT == 0) {
                image.pixels[index - 1] = pxl.color | CTRL_BIT; 
                queue.enqueue(.{
                    .y = pxl.y,
                    .x = pxl.x - 1,
                    .color = pxl.color,
                });
            }
            if (pxl.y + 1 < image.height and image.pixels[index + image.width] & CTRL_BIT == 0) {
                image.pixels[index + image.width] = pxl.color | CTRL_BIT;
                queue.enqueue(.{
                    .y = pxl.y + 1,
                    .x = pxl.x,
                    .color = pxl.color,
                });
            }
            if (pxl.x + 1 < image.width and image.pixels[index + 1] & CTRL_BIT == 0) {
                image.pixels[index + 1] = pxl.color | CTRL_BIT;
                queue.enqueue(.{
                    .y = pxl.y,
                    .x = pxl.x + 1,
                    .color = pxl.color,
                });
            }
        }
    }

    allocator.free(buf);
}
