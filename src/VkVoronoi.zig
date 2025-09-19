const std = @import("std");
const vk  = @import("vulkan");

const Allocator = std.mem.Allocator;
const assert = std.debug.assert;

const ComputeContext = @import("ComputeContext.zig");

const comp_spv align(@alignOf(u32)) = @embedFile("voronoi_comp").*;
const descriptor_set_count = 1;

ctx: *ComputeContext,
command_pool: vk.CommandPool,

image_size: u32,

descriptor_set: vk.DescriptorSet,
descriptor_pool: vk.DescriptorPool,
descriptor_set_layout: vk.DescriptorSetLayout,

pipeline: vk.Pipeline,
pipeline_layout: vk.PipelineLayout,

ssbo: vk.Buffer,
ssbo_mem: vk.DeviceMemory,

const Self = @This();

pub fn init(ctx: *ComputeContext) !Self {
    var self: Self = undefined;
    self.ctx = ctx;

    self.image_size = 1920 * 1080 * 32;
    try self.create_command_structures();
    try self.create_ssbo_with_size_estimate();
    try self.create_descriptors();
    try self.create_compute_pipeline();

    return self;
}

fn create_command_structures(self: *Self) !void {
    const pool_info = vk.CommandPoolCreateInfo {
        .flags = .{ .reset_command_buffer_bit = true },
        .queue_family_index = self.ctx.compute_family,
    };

    self.command_pool = try self.ctx.dev.createCommandPool(&pool_info, null);
}

fn create_ssbo_with_size_estimate(self: *Self) !void {
    const usage = vk.BufferUsageFlags{ .transfer_dst_bit = true, .storage_buffer_bit = true };
    const props = vk.MemoryPropertyFlags{ .device_local_bit = true };

    try self.create_buffer(self.image_size, usage, props, &self.ssbo, &self.ssbo_mem);
}

fn create_descriptors(self: *Self) !void {
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

    self.descriptor_set_layout = try self.ctx.dev.createDescriptorSetLayout(&layout_info, null);

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
    self.descriptor_pool = try self.ctx.dev.createDescriptorPool(&pool_info, null);

    const set_alloc_info = vk.DescriptorSetAllocateInfo{
        .descriptor_pool = self.descriptor_pool,
        .descriptor_set_count = descriptor_set_count,
        .p_set_layouts = @ptrCast(&self.descriptor_set_layout),
    };
    try self.ctx.dev.allocateDescriptorSets(&set_alloc_info, @ptrCast(&self.descriptor_set));

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

fn create_compute_pipeline(self: *Self) !void {
    const shader = try self.ctx.dev.createShaderModule(
        &.{ .code_size = comp_spv.len, .p_code = @ptrCast(&comp_spv) }, null
    );
    const shader_stage_info = vk.PipelineShaderStageCreateInfo{
        .stage = .{ .compute_bit = true },
        .module = shader,
        .p_name = "main",
    };

    const layout_create_info = vk.PipelineLayoutCreateInfo{
        .set_layout_count = 1, 
        .p_set_layouts = @ptrCast(&self.descriptor_set_layout),
    };
    self.pipeline_layout = try self.ctx.dev.createPipelineLayout(&layout_create_info, null);

    const compute_pipeline_create_info = vk.ComputePipelineCreateInfo{
        .layout = self.pipeline_layout, 
        .stage = shader_stage_info, 
        .base_pipeline_index = 0,
    };
    const result = try self.ctx.dev.createComputePipelines(
        .null_handle,
        1, 
        @ptrCast(&compute_pipeline_create_info),
        null,
        @ptrCast(&self.pipeline),
    );
    assert(result == .success);
}

fn create_buffer(
    self: *Self,
    size: vk.DeviceSize, 
    usage: vk.BufferUsageFlags, 
    props: vk.MemoryPropertyFlags, 
    buffer: *vk.Buffer, 
    buffer_mem: *vk.DeviceMemory
) !void {
    buffer.* = try self.ctx.dev.createBuffer(
        &.{ .size = size, .usage = usage, .sharing_mode = .exclusive }, null
    );

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

    buffer_mem.* = try self.ctx.dev.allocateMemory(
        &.{ .allocation_size = mem_reqs.size, .memory_type_index = mem_type }, null
    );
    try self.ctx.dev.bindBufferMemory(buffer.*, buffer_mem.*, 0);
}

fn copy_buffer(self: *Self, src: vk.Buffer, dst: vk.Buffer, size: vk.DeviceSize) !void {
    var cmdbuf_handle: vk.CommandBuffer = undefined;
    try self.ctx.dev.allocateCommandBuffers(&.{
        .command_pool = self.command_pool,
        .level = .primary,
        .command_buffer_count = 1,
    }, @ptrCast(&cmdbuf_handle));

    const cmd_buf = vk.CommandBufferProxy.init(cmdbuf_handle, self.ctx.dev.wrapper);

    try cmd_buf.beginCommandBuffer(&.{ .flags = .{ .one_time_submit_bit = true }});
    const region = vk.BufferCopy{
        .src_offset = 0,
        .dst_offset = 0,
        .size = size,
    };
    cmd_buf.copyBuffer(src, dst, 1, @ptrCast(&region));

    try cmd_buf.endCommandBuffer();

    const submit_info = vk.SubmitInfo{
        .command_buffer_count = 1,
        .p_command_buffers = (&cmd_buf.handle)[0..1],
        .p_wait_dst_stage_mask = undefined,
    };

    try self.ctx.dev.queueSubmit(self.ctx.compute_handle, 1, @ptrCast(&submit_info), .null_handle);
    try self.ctx.dev.queueWaitIdle(self.ctx.compute_handle);
}

pub fn deinit(self: *Self) void {
    _ = self;
}

