const std = @import("std");
const assert = std.debug.assert;

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
    
