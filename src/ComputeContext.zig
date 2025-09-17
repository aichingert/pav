const std = @import("std");
const vk = @import("vulkan");
const Allocator = std.mem.Allocator;

vkb: vk.BaseWrapper,

instance: vk.InstanceProxy,
debug_messenger: vk.DebugUtilsMessengerEXT,

pdev: vk.PhysicalDevice,
dev: vk.DeviceProxy,

compute_handle: vk.Queue,
compute_family: u32,

const Self = @This();

const DeviceCandidate = struct {
    pdev: vk.PhysicalDevice,
    compute_queue: u32,
};

const required_device_extensions = [_][*:0]const u8{vk.extensions.khr_dynamic_rendering.name};

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

fn pick_physical_device(instance: vk.InstanceProxy, allocator: Allocator) !DeviceCandidate {
    const pdevs = try instance.enumeratePhysicalDevicesAlloc(allocator);
    defer allocator.free(pdevs);
    var fallback: ?DeviceCandidate = null;

    for (pdevs) |pdev| {
        const pdev_ext_props = try instance.enumerateDeviceExtensionPropertiesAlloc(pdev, null, allocator);
        defer allocator.free(pdev_ext_props);

        for (required_device_extensions) |ext| {
            for (pdev_ext_props) |pdev_prop| {
                if (std.mem.eql(u8, std.mem.span(ext), std.mem.sliceTo(&pdev_prop.extension_name, 0))) {
                    break;
                }
            } else {
                continue;
            }
        }

        const pdev_props = instance.getPhysicalDeviceProperties(pdev);
        const families = try instance.getPhysicalDeviceQueueFamilyPropertiesAlloc(pdev, allocator);
        defer allocator.free(families);

        for (families, 0..) |props, i| {
            const family: u32 = @intCast(i);

            if          (pdev_props.device_type == .discrete_gpu and props.queue_flags.compute_bit) {
                return .{
                    .pdev = pdev,
                    .compute_queue = family,
                };
            } else if   (pdev_props.device_type == .integrated_gpu and props.queue_flags.compute_bit) {
                fallback = .{
                    .pdev = pdev,
                    .compute_queue = family,
                };
            }
        }
    }

    if (fallback) |candidate| {
        return candidate;
    }

    return error.NoSuitableDevice;
}

pub fn init(allocator: Allocator) !Self {
    var self: Self = undefined;
    self.vkb = vk.BaseWrapper.load(vk_get_instance_proc_addr);

    var extensions: std.ArrayList([*:0]const u8) = .empty;
    try extensions.append(allocator, vk.extensions.ext_debug_utils.name);

    const instance_handle = try self.vkb.createInstance(&.{
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
    vki.* = vk.InstanceWrapper.load(instance_handle, self.vkb.dispatch.vkGetInstanceProcAddr.?);
    self.instance = vk.InstanceProxy.init(instance_handle, vki);

    self.debug_messenger = try self.instance.createDebugUtilsMessengerEXT(&.{
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

    const candidate = try pick_physical_device(self.instance, allocator);
    self.pdev = candidate.pdev;

    const priority = [_]f32{1.0};
    const qci = [_]vk.DeviceQueueCreateInfo{
        .{
            .queue_family_index = candidate.compute_queue,
            .queue_count = 1,
            .p_queue_priorities = &priority,
        },
    };
    const dev = try self.instance.createDevice(self.pdev, &.{
        .queue_create_info_count = @intCast(qci.len),
        .p_queue_create_infos = &qci,
        .enabled_extension_count = required_device_extensions.len,
        .pp_enabled_extension_names = @ptrCast(&required_device_extensions),
    }, null);
    const vkd = try allocator.create(vk.DeviceWrapper);
    vkd.* = vk.DeviceWrapper.load(dev, self.instance.wrapper.dispatch.vkGetDeviceProcAddr.?);
    self.dev = vk.DeviceProxy.init(dev, vkd);

    self.compute_handle = self.dev.getDeviceQueue(candidate.compute_queue, 0);
    self.compute_family = candidate.compute_queue;

    extensions.deinit(allocator);
    return self;
}

pub fn deinit(self: *const Self, allocator: Allocator) void {
    self.dev.destroyDevice(null);
    self.instance.destroyDebugUtilsMessengerEXT(self.debug_messenger, null);
    self.instance.destroyInstance(null);

    allocator.destroy(self.dev.wrapper);
    allocator.destroy(self.instance.wrapper);
}

