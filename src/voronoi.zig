const std = @import("std");
const assert = std.debug.assert;
const mem = std.mem;
const Allocator = mem.Allocator;

const utils = @import("utils.zig");
const Image = utils.Image;
const Method = utils.Method;

pub const Queue = struct {
    buf: []u64,

    start: u64,
    end: u64,
    cap: u64,
    len: u64,

    pub fn init(buf: []u64) Queue {
        var self: Queue = undefined;

        self.buf = buf;
        self.start = 0;
        self.end = 0;
        self.len = 0;
        self.cap = buf.len;
        return self;
    }

    pub fn enqueue(self: *Queue, value: u64) void {
        if (self.end == self.cap) {
            assert(self.start != 0);
            self.end = 0;
        }
        assert(self.len < self.cap);
        self.buf[self.end] = value;
        self.end += 1;
        self.len += 1;
    }

    pub fn dequeue(self: *Queue) u64 {
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
    const random = std.crypto.random;
    const ctrl_b = 1 << 25;

    for (0..num_points) |_| {
        const x = random.intRangeAtMost(u64, 0, image.width - 1);
        const y = random.intRangeAtMost(u64, 0, image.height - 1);
        const index = y * image.width + x;

        if (image.pixels[index] & ctrl_b != ctrl_b) {
            // NOTE: should just use structs
            const color: u64 = image.pixels[index]; 
            queue.enqueue((color << 40) | (y << 20) | (x));
            image.pixels[index] |= ctrl_b;
        }

    }
}

pub fn apply(allocator: Allocator, image: *Image, method: Method) !void {
    const buf  = try allocator.alloc(u64, image.pixels.len);
    var queue = Queue.init(buf);

    const total_points: f64 = @floatFromInt(image.*.width * image.*.height);
    const points_to_place: u32 = @intFromFloat(total_points * 0.1);

    switch (method) {
        .random => place_points_random(points_to_place, &queue, image),
    }

    const ctrl_b = 1 << 25;

    while (queue.len > 0) {
        const wave_len = queue.len;

        for (0..wave_len) |_| {
            const value = queue.dequeue();
            const color = value >> 40;
            const y = (value >> 20) & 0xFFFFF;
            const x = value & 0xFFFFF;
            const index = y * image.width + x;

            if (y > 0 and image.pixels[index - image.width] & ctrl_b == 0)  {
                image.pixels[index - image.width] = @as(u32, @intCast(color)) | ctrl_b;
                queue.enqueue(color << 40 | (y - 1) << 20 | x);
            }
            if (x > 0 and image.pixels[index - 1] & ctrl_b == 0) {
                image.pixels[index - 1] = @as(u32, @intCast(color)) | ctrl_b;
                queue.enqueue(color << 40 | y << 20 | (x - 1));
            }
            if (y + 1 < image.height and image.pixels[index + image.width] & ctrl_b == 0) {
                image.pixels[index + image.width] = @as(u32, @intCast(color)) | ctrl_b;
                queue.enqueue(color << 40 | (y + 1) << 20 | x);
            }
            if (x + 1 < image.width and image.pixels[index + 1] & ctrl_b == 0) {
                image.pixels[index + 1] = @as(u32, @intCast(color)) | ctrl_b;
                queue.enqueue(color << 40 | y << 20 | (x + 1));
            }
        }
    }

    allocator.free(buf);
}
