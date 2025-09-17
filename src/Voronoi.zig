const std = @import("std");

const vk = @import("vulkan");

const utils = @import("utils.zig");
const Image = utils.Image;
const COLOR_CHANNELS = utils.COLOR_CHANNELS;

const assert = std.debug.assert;
const mem = std.mem;
const Allocator = mem.Allocator;

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

const vk_get_instance_proc_addr = @extern(vk.PfnGetInstanceProcAddr, .{
    .name = "vkGetInstanceProcAddr",
    .library_name = "vulkan",
});

fn debug_utils_messenger_callback(
    severity: vk.DebugUtilsMessageSeverityFlagsEXT, 
    msg_type: vk.DebugUtilsMessageTypeFlagsEXT, 
    callback_data: ?*const vk.DebugUtilsMessengerCallbackDataEXT, 
    _: ?*anyopaque
) callconv(.c) vk.Bool32 {
    const severity_str = 
        if (severity.verbose_bit_ext) 
            "verbose" 
        else if (severity.info_bit_ext) 
            "info" 
        else if (severity.warning_bit_ext) 
            "warning" 
        else if (severity.error_bit_ext) 
            "error" 
        else 
            "unknown";

    const type_str = 
        if (msg_type.general_bit_ext) 
            "general" 
        else if (msg_type.validation_bit_ext) 
            "validation" 
        else if (msg_type.performance_bit_ext) 
            "performance" 
        else if (msg_type.device_address_binding_bit_ext) 
            "device addr" 
        else 
            "unknown";

    const message: [*c]const u8 = if (callback_data) |cb_data| cb_data.p_message else "NO MESSAGE!";
    std.debug.print("[{s}][{s}]. Message:\n  {s}\n", .{ severity_str, type_str, message });
    return .false;
}

pub fn apply(allocator: Allocator, image: *Image, method: Method) !void {
    const vkb = vk.BaseWrapper.load(vk_get_instance_proc_addr);

    var extensions: std.ArrayList([*:0]const u8) = .empty;
    try extensions.append(allocator, vk.extensions.ext_debug_utils.name);

    const instance_handle = try vkb.createInstance(&.{
        .p_application_info = &.{
            .p_application_name = "compute voronoi",
            .application_version = @bitCast(vk.makeApiVersion(0, 0, 0, 0)),
            .engine_version = @bitCast(vk.makeApiVersion(0, 0, 0, 0)),
            .api_version = @bitCast(vk.makeApiVersion(0, 1, 4, 0)),
        },
        .enabled_extension_count = @intCast(extensions.items.len),
        .pp_enabled_extension_names = extensions.items.ptr,
        .flags = .{ .enumerate_portability_bit_khr = true },
    }, null);

    const vki = try allocator.create(vk.InstanceWrapper);
    vki.* = vk.InstanceWrapper.load(instance_handle, vkb.dispatch.vkGetInstanceProcAddr.?);
    const instance = vk.InstanceProxy.init(instance_handle, vki);

    const debug_messenger = try instance.createDebugUtilsMessengerEXT(&.{
        .message_severity = .{
            .info_bit_ext = true,
            .warning_bit_ext = true,
            .error_bit_ext = true,
        },
        .message_type = .{
            .general_bit_ext = true,
            .validation_bit_ext = true,
            .performance_bit_ext = true,
        },
        .pfn_user_callback = &debug_utils_messenger_callback,
        .p_user_data = null,
    }, null);
    _ = debug_messenger;

    extensions.deinit(allocator);
    allocator.destroy(vki);


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

            var dst_idx = i * image.*.width * COLOR_CHANNELS + j * COLOR_CHANNELS;
            var src_idx = closest.y * image.*.width * COLOR_CHANNELS + closest.x * COLOR_CHANNELS;
            var colors: u8 = 0;

            while (colors < COLOR_CHANNELS) {
                image.*.pixels[dst_idx] = image.*.pixels[src_idx];
                colors += 1;
                dst_idx += 1;
                src_idx += 1;
                cnt += 1;
            }
            j += 1;
        }

        i += 1;
    }
}
