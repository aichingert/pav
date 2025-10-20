pub const RGB: u8 = 3;
pub const RGBA: u8 = 4;

pub const ImageType = enum {
    png,
    jpg,
    webp,
};

pub const Method = enum(u8) {
    random = 0,
};

pub const VoronoiConfig = struct {
    init: Method,
    seeds: u32,
};

pub const Image = struct {
    width: u32,
    height: u32,
    pixels: []u32,
};

pub const ParseImageError = error {
    ThisError,
    NotSupported,
    InvalidImage,
};

pub fn read(comptime T: type, slice: []const u8, pos: *u32) T {
    const len: T = @bitSizeOf(T) / 8;
    const byt: T = 8;
    var value: T = 0;

    var i: T = 0;
    while (i < len) {
        value |= @as(T, slice[pos.* + i]) << @intCast((byt * (len - i - 1)));
        i += 1;
    }

    pos.* += len;
    return value;
}

pub fn read_slice(slice: []const u8, pos: *u32, len: u32) []const u8 {
    const sliced = slice[pos.*..pos.* + len];
    pos.* += len;
    return sliced;
}

