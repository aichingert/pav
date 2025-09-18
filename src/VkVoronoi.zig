const std = @import("std");
const vk  = @import("vulkan");

const Allocator = std.mem.Allocator;

const ComputeContext = @import("ComputeContext.zig");

const comp_spv align(@alignOf(u32)) = @embedFile("voronoi_comp").*;
const descriptor_set_count = 1;

ctx: *ComputeContext,

image_size: u32 = 32 * 1920 * 1080,

descriptor_set: vk.DescriptorSet,
descriptor_pool: vk.DescriptorPool,
descriptor_set_layout: vk.DescriptorSetLayout,

pipeline: vk.Pipeline,

ssbo: vk.Buffer,
ssbo_mem: vk.DeviceMemory,

const Self = @This();

pub fn init(ctx: *ComputeContext) Self {
    var self: Self = undefined;
    self.ctx = ctx;
    self.create_descriptors();

    const shader_create_info: vk.ShaderModuleCreateInfo = .{
        .code_size = comp_spv.len,
        .p_code = @ptrCast(&comp_spv),
    };

    const shader = ctx.dev.createShaderModule(&shader_create_info, null) catch |err| {
        std.debug.print("ERROR: shader - {any}\n", .{err});
        std.process.exit(1);
    };
    const shader_stage_info = vk.PipelineShaderStageCreateInfo{
        .stage = .{ .compute_bit = true },
        .module = shader,
        .p_name = "main",
    };
    _ = shader_stage_info;


    return self;
}

fn create_descriptors(self: *Self) void {
    const layout_bindings = [_]vk.DescriptorSetLayoutBinding{
        .{
            .binding = 0,
            .descriptor_count = 1,
            .descriptor_type = .storage_buffer,
            .stage_flags = .{ .compute_bit = true },
        },
    };

    const layout_info = vk.DescriptorSetLayoutCreateInfo{
        .binding_count = @intCast(layout_bindings.len),
        .p_bindings = &layout_bindings,
    };

    self.descriptor_set_layout = self.ctx.dev.createDescriptorSetLayout(&layout_info, null) catch |err| {
        std.debug.print("ERROR: descriptor set layout - {any}\n", .{err});
        std.process.exit(1);
    };

    const pool_sizes = [_]vk.DescriptorPoolSize {
        .{
            .type = .storage_buffer,
            .descriptor_count = 1,
        },
    };
    const pool_info = vk.DescriptorPoolCreateInfo {
        .pool_size_count = @intCast(pool_sizes.len),
        .p_pool_sizes = &pool_sizes,
        .max_sets = descriptor_set_count,
    };
    self.descriptor_pool = self.ctx.dev.createDescriptorPool(&pool_info, null) catch |err| {
        std.debug.print("ERROR: descriptor pool - {any}\n", .{err});
        std.process.exit(1);
    };

    const set_alloc_info = vk.DescriptorSetAllocateInfo{
        .descriptor_pool = self.descriptor_pool,
        .descriptor_set_count = descriptor_set_count,
        .p_set_layouts = @ptrCast(&self.descriptor_set_layout),
    };

    self.ctx.dev.allocateDescriptorSets(&set_alloc_info, @ptrCast(&self.descriptor_set)) catch |err| {
        std.debug.print("ERROR: descriptor set - {any}\n", .{err});
        std.process.exit(1);
    };

    const sb_info = [_]vk.DescriptorBufferInfo {
        .{
            .buffer = self.ssbo,
            .offset = 0,
            .range = self.image_size,
        }
    };
    const texel_buffer_view = [_]vk.BufferView{};
    const image_info = [_]vk.DescriptorImageInfo{};

    const desc_write = [_]vk.WriteDescriptorSet{
        .{
            .dst_set = self.descriptor_set,
            .dst_binding = 0,
            .dst_array_element = 0,
            .descriptor_type = .storage_buffer,
            .descriptor_count = 1,
            .p_buffer_info = @ptrCast(&sb_info),
            .p_texel_buffer_view = @ptrCast(&texel_buffer_view),
            .p_image_info = @ptrCast(&image_info),
        }
    };

    self.ctx.dev.updateDescriptorSets(@intCast(desc_write.len), @ptrCast(&desc_write), 0, null);
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
