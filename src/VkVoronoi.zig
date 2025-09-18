const std = @import("std");
const vk  = @import("vulkan");

const Allocator = std.mem.Allocator;

const ComputeContext = @import("ComputeContext.zig");

const comp_spv align(@alignOf(u32)) = @embedFile("voronoi_comp").*;

ctx: *ComputeContext,

ssbo: vk.Buffer,
ssbo_mem: vk.DeviceMemory,

const Self = @This();

pub fn init(ctx: *ComputeContext) Self {
    var self: Self = undefined;
    self.ctx = ctx;

    return self;
}

fn create_buffer(
    self: *Self,
    size: vk.DeviceSize, 
    usage: vk.BufferUsageFlags, 
    props: vk.MemoryPropertyFlags, 
    buffer: *vk.Buffer, 
    buffer_mem: *vk.DeviceMemory
) !void {
    const buffer_info = vk.BufferCreateInfo{
        .size = size,
        .usage = usage,
        .sharing_mode = .exclusive,
    };

    buffer.* = try self.ctx.dev.createBuffer(&buffer_info, null);

    var mem_type: u32 = 0;
    const mem_reqs = self.ctx.dev.getBufferMemoryRequirements(buffer.*);
    const mem_props = self.ctx.instance.getPhysicalDeviceMemoryProperties(self.ctx.pdev);

    while (mem_type < mem_props.memory_type_count) : (mem_type += 1) {
        const m_type: u32 = @as(u32, 1) << @intCast(mem_type);

        if ((mem_reqs.memory_type_bits & m_type) == m_type 
            and 
            mem_props.memory_types[mem_type].property_flags == props
        ) {
            break;
        }
    }

    const alloc_info = vk.MemoryAllocateInfo{
        .allocation_size = mem_reqs.size,
        .memory_type_index = mem_type,
    };

    buffer_mem.* = try self.ctx.dev.allocateMemory(&alloc_info, null);

    self.ctx.dev.bindBufferMemory(buffer.*, buffer_mem.*, 0) catch |err| {
        std.debug.print("{any}\n", .{err});
    };
}

pub fn allocate_image_memory(self: *Self, allocator: Allocator) void {
    _ = allocator;

    var staging_buffer: vk.Buffer = undefined;
    var staging_buffer_mem: vk.DeviceMemory = undefined;

    self.create_buffer(7680 * 4320 * 32, .{ .transfer_src_bit = true }, .{ .host_visible_bit = true, .host_coherent_bit = true }, &staging_buffer, &staging_buffer_mem) catch |err| {
        std.debug.print("{any}\n", .{err});
        std.process.exit(1);
    };
}
