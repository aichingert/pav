const std = @import("std");
const mem = std.mem;
const vk  = @import("vulkan");

const Allocator = mem.Allocator;
const assert = std.debug.assert;

const utils = @import("utils.zig");
const Image = utils.Image;
const Method = utils.Method;
const ComputeContext = @import("ComputeContext.zig");

const comp_spv align(@alignOf(u32)) = @embedFile("voronoi_comp").*;
const descriptor_set_count = 1;

// NOTE: this is used to not use the
// entirety of the mapped buffer but
// only up to a certain point since it
// crashes the application at random places
// if it uses the entire buffer
// TODO: fix this
const HACK_OFFSET: u64 = 15_000_000;

const Vp = extern struct {
    color: u32,
    point: u32,
    padding: [2]u32,
};

const PerImageData = extern struct {
    p1: Vp,
    p2: Vp,
};

const VkBuffer = struct {
    buf: vk.Buffer,
    mem: vk.DeviceMemory,
    size: u64,

    fn destroy(self: *VkBuffer, dev: vk.DeviceProxy) void {
        dev.destroyBuffer(self.buf, null);
        dev.freeMemory(self.mem, null);
    }
};

ctx: *ComputeContext,

command_pool: vk.CommandPool,
command_buffer: vk.CommandBufferProxy,

limits: vk.PhysicalDeviceLimits,

descriptor_set: vk.DescriptorSet,
descriptor_pool: vk.DescriptorPool,
descriptor_set_layout: vk.DescriptorSetLayout,

pipeline: vk.Pipeline,
pipeline_layout: vk.PipelineLayout,

image_buffer: VkBuffer,
per_image_data: VkBuffer,

const Self = @This();

pub fn init(ctx: *ComputeContext) !Self {
    var self: Self = undefined;
    self.ctx = ctx;

    self.limits = self.ctx.instance.getPhysicalDeviceProperties(
        self.ctx.pdev
    ).limits;

    try self.create_command_structures();
    try self.create_image_buffer();
    try self.create_per_image_data();
    try self.create_descriptors();
    try self.create_compute_pipeline();

    return self;
}

fn init_voronoi(self: *Self, img: *Image, method: Method) !u32 {
    assert(method == .random);

    const rndm = std.crypto.random;
    const size = img.width * img.height;

    _ = size;
    _ = self;

    const x1 = rndm.intRangeAtMost(u32, 0, img.width - 1);
    const y1 = rndm.intRangeAtMost(u32, 0, img.height - 1);
    const x2 = rndm.intRangeAtMost(u32, 0, img.width - 1);
    const y2 = rndm.intRangeAtMost(u32, 0, img.height - 1);

    var dis = @max(img.width - x1, x1);
    dis = @max(dis, img.width - x2);
    dis = @max(dis, x2);
    dis = @max(dis, img.height - y1);
    dis = @max(dis, y1);
    dis = @max(dis, img.height - y2);
    dis = @max(dis, y2);

    img.pixels[y1 * img.width + x1] |= 1 << 25;
    img.pixels[y2 * img.width + x2] |= 1 << 25;
    return std.math.ceilPowerOfTwo(u32, dis / 2 + 1);
}

fn upload_image_data(self: *Self, img: *Image, offset: u64) !void {
    const usage = vk.BufferUsageFlags{ 
        .transfer_src_bit = true, 
        .storage_buffer_bit = true 
    };
    const props = vk.MemoryPropertyFlags{ 
        .host_visible_bit = true, 
        .host_coherent_bit = true 
    };

    const buf_size = self.image_buffer.size;
    var staging = try self.create_buffer(buf_size, usage, props);
    const data = try self.ctx.dev.mapMemory(staging.mem, 0, buf_size, .{});
    const gpu_pixels: [*]u32 = @ptrCast(@alignCast(data));
    const copy_size = @min(img.pixels.len - offset, buf_size - HACK_OFFSET);

    @memcpy(gpu_pixels[0..copy_size], img.pixels[offset..offset + copy_size]);
    try self.copy_buffer(staging, self.image_buffer);

    staging.destroy(self.ctx.dev);
}

fn store_image_data(self: *Self, img: *Image, offset: u64) !void {
    const usage = vk.BufferUsageFlags{ 
        .transfer_dst_bit = true, 
        .storage_buffer_bit = true 
    };
    const props = vk.MemoryPropertyFlags{ 
        .host_visible_bit = true, 
        .host_coherent_bit = true 
    };

    const buf_size = self.image_buffer.size; 
    var staging = try self.create_buffer(buf_size, usage, props);
    try self.copy_buffer(self.image_buffer, staging);

    const data = try self.ctx.dev.mapMemory(staging.mem, 0, buf_size, .{});
    const gpu_pixels: [*]u32 = @ptrCast(@alignCast(data));
    const copy_size = @min(img.pixels.len - offset, buf_size - HACK_OFFSET);

    @memcpy(img.pixels[offset..offset + copy_size], gpu_pixels[0..copy_size]);
    staging.destroy(self.ctx.dev);
}

fn run_wave(self: *Self, img: *Image) !void {
    const img_size = @as(u64, img.width) * @as(u64, img.height);
    const buf_size = self.image_buffer.size;

    var offset: u64 = 0;
    // NOTE: maybe implement this in a way so people 
    // could optimize group size to use their hardware
    const inc:  u64 = @min(
        self.limits.max_compute_work_group_size[0] * 1024,
        buf_size - HACK_OFFSET);

    while (offset < img_size) : (offset += inc) {
        try self.upload_image_data(img, offset);
        try self.command_buffer.beginCommandBuffer(&.{});

        self.command_buffer.bindPipeline(.compute, self.pipeline);
        self.command_buffer.bindDescriptorSets(
            .compute, 
            self.pipeline_layout, 
            0, 
            1, 
            @ptrCast(&self.descriptor_set), 
            0, 
            null);
        self.command_buffer.dispatch(
            self.limits.max_compute_work_group_size[0], 
            1, 
            1);

        try self.command_buffer.endCommandBuffer();
        const submit_info = vk.SubmitInfo{
            .command_buffer_count = 1,
            .p_command_buffers = @ptrCast(&self.command_buffer),
            .p_wait_dst_stage_mask = undefined,
        };
        try self.ctx.dev.queueSubmit(
            self.ctx.compute_handle, 
            1, 
            @ptrCast(&submit_info), 
            .null_handle);
        try self.ctx.dev.queueWaitIdle(self.ctx.compute_handle);
        try self.store_image_data(img, offset);
    }
}

// TODO: implement
pub fn compute(self: *Self, img: *Image, method: Method) !void {
    _ = method;
    //const steps = try self.init_voronoi(img, method);

    try self.run_wave(img);
    //for (0..steps) |_|  {
    //    try self.run_wave(img);
    //}
}

fn create_command_structures(self: *Self) !void {
    const pool_info = vk.CommandPoolCreateInfo {
        .flags = .{ .reset_command_buffer_bit = true },
        .queue_family_index = self.ctx.compute_family,
    };

    self.command_pool = try self.ctx.dev.createCommandPool(
        &pool_info, 
        null);

    var cmd_buf_handle: vk.CommandBuffer = undefined;
    const alloc_info = vk.CommandBufferAllocateInfo{
        .command_pool = self.command_pool, 
        .level = .primary, 
        .command_buffer_count = 1,
    };
    try self.ctx.dev.allocateCommandBuffers(
        &alloc_info, 
        @ptrCast(&cmd_buf_handle));
    self.command_buffer = vk.CommandBufferProxy.init(
        cmd_buf_handle, 
        self.ctx.dev.wrapper);
}

fn create_image_buffer(self: *Self) !void {
    const usage = vk.BufferUsageFlags{ 
        .transfer_src_bit = true, 
        .transfer_dst_bit = true, 
        .storage_buffer_bit = true 
    };
    const props = vk.MemoryPropertyFlags{ 
        .device_local_bit = true 
    };


    // TODO: look at the note on top :(
    
    // TODO: figure out how to check
    // the maximum size for the current 
    // device and use this as a metric

    // NOTE: this might not even be the error??
    // NOTE: if this is 1 << 15 it starts to crash
    // without any reason at all I HATE ZIG THIS 
    // LANGUAGE ARGHHH

    const chunk_size: u64 = 1 << 24;
    assert(chunk_size > 100_000 + HACK_OFFSET);

    self.image_buffer = try self.create_buffer(
        chunk_size,
        usage, 
        props);
}

fn create_per_image_data(self: *Self) !void {
    const size: vk.DeviceSize = @sizeOf(PerImageData);
    std.debug.print("pid size:{any}\n", .{size});
    const usage = vk.BufferUsageFlags{
        .uniform_buffer_bit = true,
    };
    const props = vk.MemoryPropertyFlags{
        .host_visible_bit = true,
        .host_coherent_bit = true,
    };
    self.per_image_data = try self.create_buffer(size, usage, props);

    const a_gpu = try self.ctx.dev.mapMemory(
        self.per_image_data.mem, 
        0, 
        size, 
        .{});
    const data: *PerImageData = @ptrCast(@alignCast(a_gpu.?));
    data.* = PerImageData{
        .p1 = .{
            .color = 0xFF0000,
            .point = 1120 * 747 / 2,
            .padding = [2]u32{0,0},
        },
        .p2 = .{
            .color = 0x0000FF,
            .point = 0,
            .padding = [2]u32{0,0},
        },
    };

    //std.mem.copyForwards(u8, @as([*]u8, @ptrCast(a_gpu))[0..@sizeOf(PerImageData)], std.mem.asBytes(&d_cpu));
}

fn create_descriptors(self: *Self) !void {
    const layout_bindings = [_]vk.DescriptorSetLayoutBinding{
        .{
            .binding = 0,
            .descriptor_count = 1,
            .descriptor_type = .uniform_buffer,
            .stage_flags = .{ .compute_bit = true },
        },
        .{
            .binding = 1,
            .descriptor_count = 1,
            .descriptor_type = .storage_buffer,
            .stage_flags = .{ .compute_bit = true },
        },
    };

    const layout_info = vk.DescriptorSetLayoutCreateInfo{
        .binding_count = @intCast(layout_bindings.len),
        .p_bindings = &layout_bindings,
    };

    self.descriptor_set_layout = try self.ctx.dev.createDescriptorSetLayout(
        &layout_info, 
        null);

    const pool_sizes = [_]vk.DescriptorPoolSize {
        .{
            .type = .uniform_buffer,
            .descriptor_count = 1,
        },
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
    self.descriptor_pool = try self.ctx.dev.createDescriptorPool(
        &pool_info, 
        null);

    const set_alloc_info = vk.DescriptorSetAllocateInfo{
        .descriptor_pool = self.descriptor_pool,
        .descriptor_set_count = descriptor_set_count,
        .p_set_layouts = @ptrCast(&self.descriptor_set_layout),
    };
    try self.ctx.dev.allocateDescriptorSets(
        &set_alloc_info, 
        @ptrCast(&self.descriptor_set));

    const ub_info = [_]vk.DescriptorBufferInfo {
        .{
            .buffer = self.per_image_data.buf,
            .offset = 0,
            .range  = self.per_image_data.size,
        },
    };
    const sb_info = [_]vk.DescriptorBufferInfo {
        .{
            .buffer = self.image_buffer.buf,
            .offset = 0,
            .range = self.image_buffer.size,
        }
    };
    const texel_buffer_view = [_]vk.BufferView{};
    const image_info = [_]vk.DescriptorImageInfo{};

    const desc_write = [_]vk.WriteDescriptorSet{
        .{
            .dst_set = self.descriptor_set,
            .dst_binding = 0,
            .dst_array_element = 0,
            .descriptor_type = .uniform_buffer,
            .descriptor_count = 1,
            .p_buffer_info = @ptrCast(&ub_info),
            .p_texel_buffer_view = @ptrCast(&texel_buffer_view),
            .p_image_info = @ptrCast(&image_info),
        },
        .{
            .dst_set = self.descriptor_set,
            .dst_binding = 1,
            .dst_array_element = 0,
            .descriptor_type = .storage_buffer,
            .descriptor_count = 1,
            .p_buffer_info = @ptrCast(&sb_info),
            .p_texel_buffer_view = @ptrCast(&texel_buffer_view),
            .p_image_info = @ptrCast(&image_info),
        }
    };

    self.ctx.dev.updateDescriptorSets(
        @intCast(desc_write.len), 
        @ptrCast(&desc_write), 
        0, 
        null);
}

fn create_compute_pipeline(self: *Self) !void {
    const shader = try self.ctx.dev.createShaderModule(
        &.{ 
            .code_size = comp_spv.len, 
            .p_code = @ptrCast(&comp_spv) 
        }, 
        null);
    defer self.ctx.dev.destroyShaderModule(shader, null);
    const shader_stage_info = vk.PipelineShaderStageCreateInfo{
        .stage = .{ 
            .compute_bit = true 
        },
        .module = shader,
        .p_name = "main",
    };

    const layout_create_info = vk.PipelineLayoutCreateInfo{
        .set_layout_count = 1, 
        .p_set_layouts = @ptrCast(&self.descriptor_set_layout),
    };
    self.pipeline_layout = try self.ctx.dev.createPipelineLayout(
        &layout_create_info, 
        null);

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
        @ptrCast(&self.pipeline));
    assert(result == .success);
}

fn find_memory_type_index(
    mem_props: vk.PhysicalDeviceMemoryProperties, 
    memory_type_bits: u32, 
    flags: vk.MemoryPropertyFlags
) !u32 {
    for (mem_props.memory_types[0..mem_props.memory_type_count], 0..) |mem_type, i| {
        if (memory_type_bits & (@as(u32, 1) << @truncate(i)) != 0 and mem_type.property_flags.contains(flags)) {
            return @truncate(i);
        }
    }

    return error.NoSuitableMemoryType;
}

fn create_buffer(
    self: *Self,
    size: vk.DeviceSize, 
    usage: vk.BufferUsageFlags, 
    props: vk.MemoryPropertyFlags, 
) !VkBuffer {
    const buf: vk.Buffer = try self.ctx.dev.createBuffer(
        &.{ 
            .size = size, 
            .usage = usage, 
            .sharing_mode = .exclusive 
        }, 
        null);

    const mem_reqs = self.ctx.dev.getBufferMemoryRequirements(buf);
    const mem_props = self.ctx.instance.getPhysicalDeviceMemoryProperties(
        self.ctx.pdev);
    const mem_index = try find_memory_type_index(
        mem_props, 
        mem_reqs.memory_type_bits, 
        props);

    const buf_mem = try self.ctx.dev.allocateMemory(
        &.{ 
            .allocation_size = mem_reqs.size, 
            .memory_type_index = mem_index 
        }, 
        null);
    try self.ctx.dev.bindBufferMemory(buf, buf_mem, 0);

    return VkBuffer{
        .buf = buf,
        .mem = buf_mem,
        .size = size,
    };
}

fn copy_buffer(self: *Self, src: VkBuffer, dst: VkBuffer) !void {
    var cmdbuf_handle: vk.CommandBuffer = undefined;
    try self.ctx.dev.allocateCommandBuffers(
        &.{
            .command_pool = self.command_pool,
            .level = .primary,
            .command_buffer_count = 1,
        }, 
        @ptrCast(&cmdbuf_handle));
    const cmd_buf = vk.CommandBufferProxy.init(
        cmdbuf_handle, 
        self.ctx.dev.wrapper);

    try cmd_buf.beginCommandBuffer(
        &.{ 
            .flags = .{ .one_time_submit_bit = true }
        });
    const region = vk.BufferCopy{
        .src_offset = 0,
        .dst_offset = 0,
        .size = src.size,
    };
    cmd_buf.copyBuffer(src.buf, dst.buf, 1, @ptrCast(&region));

    try cmd_buf.endCommandBuffer();

    const submit_info = vk.SubmitInfo{
        .command_buffer_count = 1,
        .p_command_buffers = (&cmd_buf.handle)[0..1],
        .p_wait_dst_stage_mask = undefined,
    };

    try self.ctx.dev.queueSubmit(
        self.ctx.compute_handle, 
        1, 
        @ptrCast(&submit_info), 
        .null_handle);
    try self.ctx.dev.queueWaitIdle(self.ctx.compute_handle);
    self.ctx.dev.freeCommandBuffers(self.command_pool, 1, @ptrCast(&cmdbuf_handle));
}

pub fn deinit(self: *Self) void {
    self.image_buffer.destroy(self.ctx.dev);
    self.per_image_data.destroy(self.ctx.dev);

    self.ctx.dev.destroyDescriptorPool(self.descriptor_pool, null);
    self.ctx.dev.destroyDescriptorSetLayout(self.descriptor_set_layout, null);
    self.ctx.dev.destroyCommandPool(self.command_pool, null);
    self.ctx.dev.destroyPipelineLayout(self.pipeline_layout, null);
    self.ctx.dev.destroyPipeline(self.pipeline, null);
}

