const std = @import("std");
const adventvk = @import("adventvk");

const Buffer = @import("Buffer.zig");
const CommandList = @import("CommandList.zig");

const VkResult = @import("VkResult.zig");
const VkAllocator = @import("VkAllocator.zig");

const Device = @This();

allocator: *std.mem.Allocator,
vk_allocator: adventvk.VkAllocationCallbacks = .{},
vk_data: adventvk.VkData = .{},

command_pool: adventvk.VkCommandPool = null,
primary_command_buffers: [3]adventvk.VkCommandBuffer = undefined,
primary_command_buffer_index: u32 = 0,
secondary_command_buffers: [10]adventvk.VkCommandBuffer = undefined,
secondary_command_buffer_usage: [10]bool = undefined,

semaphores: [3]adventvk.VkSemaphore = undefined,
semaphore_index: u32 = 0,
fences: [3]adventvk.VkFence = undefined,

submitted_command_buffers: std.ArrayList(adventvk.VkCommandBuffer) = .empty,

descriptor_pool: adventvk.VkDescriptorPool = null,

fn debug_callback(severity: c_uint, message_types: u32, callback_data: [*c]const adventvk.VkDebugUtilsMessengerCallbackDataEXT, user_data: ?*anyopaque) callconv(.c) u32 {
    if (severity < adventvk.VK_DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT)
        return adventvk.VK_FALSE;

    std.debug.print("[Validation Layer] {s}", .{ callback_data.*.pMessage });

    _ = message_types;
    _ = user_data;

    return adventvk.VK_FALSE;
}

pub fn init(self: *Device, allocator: *std.mem.Allocator) !void {
    self.* = .{ .allocator = allocator };
    self.vk_allocator = VkAllocator.makeCallbacks(allocator);
    self.vk_data = adventvk.setupVulkan(&self.vk_allocator, &debug_callback);

    const command_pool_info = adventvk.VkCommandPoolCreateInfo{
        .sType = adventvk.VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
        .queueFamilyIndex = self.vk_data.queueFamily
    };

    var result = adventvk.vkCreateCommandPool(self.vk_data.device, &command_pool_info, self.vk_data.allocator, &self.command_pool);
    try VkResult.check(result);

    var command_buffer_alloc_info = adventvk.VkCommandBufferAllocateInfo{
        .sType = adventvk.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
        .commandBufferCount = @intCast(self.secondary_command_buffers.len),
        .commandPool = self.command_pool,
        .level = adventvk.VK_COMMAND_BUFFER_LEVEL_SECONDARY,
    };

    result = adventvk.vkAllocateCommandBuffers(self.vk_data.device, &command_buffer_alloc_info, &self.secondary_command_buffers);
    try VkResult.check(result);

    command_buffer_alloc_info.commandBufferCount = @intCast(self.primary_command_buffers.len);
    command_buffer_alloc_info.level = adventvk.VK_COMMAND_BUFFER_LEVEL_PRIMARY;

    result = adventvk.vkAllocateCommandBuffers(self.vk_data.device, &command_buffer_alloc_info, &self.primary_command_buffers);
    try VkResult.check(result);

    for (0..self.secondary_command_buffer_usage.len) |i| {
        self.secondary_command_buffer_usage[i] = false;
    }

    const pool_sizes = &[_]adventvk.VkDescriptorPoolSize{
        .{
            .type = adventvk.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
            .descriptorCount = 100,
        },
        .{
            .type = adventvk.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
            .descriptorCount = 100,
        },
        .{
            .type = adventvk.VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE,
            .descriptorCount = 100,
        },
        .{
            .type = adventvk.VK_DESCRIPTOR_TYPE_SAMPLER,
            .descriptorCount = 100,
        },
        .{
            .type = adventvk.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,
            .descriptorCount = 100,
        }
    };

    const pool_info = adventvk.VkDescriptorPoolCreateInfo{
        .sType = adventvk.VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,
        .poolSizeCount = @intCast(pool_sizes.len),
        .pPoolSizes = pool_sizes,
        .maxSets = 100 * pool_sizes.len,
        .flags = adventvk.VK_DESCRIPTOR_POOL_CREATE_FREE_DESCRIPTOR_SET_BIT,
    };

    result = adventvk.vkCreateDescriptorPool(self.vk_data.device, &pool_info, self.vk_data.allocator, &self.descriptor_pool);
    try VkResult.check(result);

    const semaphore_info = adventvk.VkSemaphoreCreateInfo{
        .sType = adventvk.VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO,
    };

    for (0..self.semaphores.len) |i| {
        result = adventvk.vkCreateSemaphore(self.vk_data.device, &semaphore_info, self.vk_data.allocator, &self.semaphores[i]);
        try VkResult.check(result);
    }

    // signal first semaphore
    const semaphore_signal_submit_info = adventvk.VkSubmitInfo{
        .sType = adventvk.VK_STRUCTURE_TYPE_SUBMIT_INFO,
        .commandBufferCount = 0,
        .signalSemaphoreCount = 1,
        .pSignalSemaphores = &self.semaphores[0]
    };
    result = adventvk.vkQueueSubmit(self.vk_data.queue, 1, &semaphore_signal_submit_info, null);
    try VkResult.check(result);

    const fence_info = adventvk.VkFenceCreateInfo{
        .sType = adventvk.VK_STRUCTURE_TYPE_FENCE_CREATE_INFO,
    };

    for (0..self.fences.len) |i| {
        result = adventvk.vkCreateFence(self.vk_data.device, &fence_info, self.vk_data.allocator, &self.fences[i]);
        try VkResult.check(result);
    }
}

pub fn deinit(self: *Device) void {
    self.submitted_command_buffers.deinit(self.allocator.*);

    for (self.semaphores) |semaphore| {
        adventvk.vkDestroySemaphore(self.vk_data.device, semaphore, self.vk_data.allocator);
    }

    for (self.fences) |fence| {
        adventvk.vkDestroyFence(self.vk_data.device, fence, self.vk_data.allocator);
    }

    adventvk.vkDestroyDescriptorPool(self.vk_data.device, self.descriptor_pool, self.vk_data.allocator);
    adventvk.vkDestroyCommandPool(self.vk_data.device, self.command_pool, self.vk_data.allocator);

    adventvk.releaseVulkan(&self.vk_data);
}

pub fn submitCommandList(self: *Device, command_list: *const CommandList) !void {
    var command_buffer: adventvk.VkCommandBuffer = null;
    for (0..self.secondary_command_buffers.len) |i| {
        if (!self.secondary_command_buffer_usage[i]) {
            command_buffer = self.secondary_command_buffers[i];
            self.secondary_command_buffer_usage[i] = true;
            break;
        }
    }

    const inheritance_info = adventvk.VkCommandBufferInheritanceInfo{
        .sType = adventvk.VK_STRUCTURE_TYPE_COMMAND_BUFFER_INHERITANCE_INFO,
    };

    const begin_info = adventvk.VkCommandBufferBeginInfo{
        .sType = adventvk.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
        .pInheritanceInfo = &inheritance_info,
    };

    var result = adventvk.vkBeginCommandBuffer(command_buffer, &begin_info);
    try VkResult.check(result);

    for (command_list.getCommands()) |command| {
        executeCommand(command_buffer, &command);
    }

    result = adventvk.vkEndCommandBuffer(command_buffer);
    try VkResult.check(result);

    try self.submitted_command_buffers.append(self.allocator.*, command_buffer);
}

fn executeCommand(command_buffer: adventvk.VkCommandBuffer, command: *const CommandList.Command) void {
    switch (command.*) {
        .bind_pipeline => |bind_pipeline_info| {
            adventvk.vkCmdBindPipeline(
                command_buffer,
                adventvk.VK_PIPELINE_BIND_POINT_COMPUTE,
                bind_pipeline_info.pipeline.pipeline
            );
        },
        .push_constants => |*push_constants_info| {
            adventvk.vkCmdPushConstants(
                command_buffer,
                push_constants_info.pipeline.pipeline_layout,
                @bitCast(push_constants_info.stage),
                push_constants_info.offset,
                push_constants_info.size,
                &push_constants_info.data
            );
        },
        .bind_shader_resource => |bind_shader_resource_info| {
            adventvk.vkCmdBindDescriptorSets(
                command_buffer,
                adventvk.VK_PIPELINE_BIND_POINT_COMPUTE,
                bind_shader_resource_info.pipeline.pipeline_layout,
                bind_shader_resource_info.set,
                1,
                &bind_shader_resource_info.resource.set,
                0,
                null
            );
        },
        .dispatch => |dispatch_info| {
            adventvk.vkCmdDispatch(
                command_buffer,
                dispatch_info.group_count_x,
                dispatch_info.group_count_y,
                dispatch_info.group_count_z
            );
        },
        .copy_buffer => |copy_buffer_info| {
            const copy = adventvk.VkBufferCopy{
                .srcOffset = copy_buffer_info.src_offset,
                .dstOffset = copy_buffer_info.dst_offset,
                .size = copy_buffer_info.size,
            };

            adventvk.vkCmdCopyBuffer(
                command_buffer,
                copy_buffer_info.src_buffer.buffer,
                copy_buffer_info.dst_buffer.buffer,
                1,
                &copy
            );
        },
        .buffer_memory_barrier => |buffer_memory_barrier_info| {
            const barrier = adventvk.VkBufferMemoryBarrier{
                .sType = adventvk.VK_STRUCTURE_TYPE_BUFFER_MEMORY_BARRIER,
                .srcAccessMask = @bitCast(buffer_memory_barrier_info.wait_for),
                .dstAccessMask = @bitCast(buffer_memory_barrier_info.access),
                .srcQueueFamilyIndex = adventvk.VK_QUEUE_FAMILY_IGNORED,
                .dstQueueFamilyIndex = adventvk.VK_QUEUE_FAMILY_IGNORED,
                .buffer = buffer_memory_barrier_info.buffer.buffer,
                .offset = 0,
                .size = adventvk.VK_WHOLE_SIZE,
            };

            adventvk.vkCmdPipelineBarrier(
                command_buffer,
                @bitCast(buffer_memory_barrier_info.wait_stage),
                @bitCast(buffer_memory_barrier_info.until_stage),
                0,
                0, null,
                1, &barrier,
                0, null,
            );
        },
        .memory_barrier => |memory_barrier_info| {
            const barrier = adventvk.VkMemoryBarrier{
                .sType = adventvk.VK_STRUCTURE_TYPE_MEMORY_BARRIER,
                .srcAccessMask = adventvk.VK_ACCESS_SHADER_WRITE_BIT,
                .dstAccessMask = adventvk.VK_ACCESS_SHADER_READ_BIT,
            };

            adventvk.vkCmdPipelineBarrier(
                command_buffer,
                toPipelineStage(memory_barrier_info.from),
                toPipelineStage(memory_barrier_info.to),
                0,
                1, &barrier,
                0, null,
                0, null,
            );
        },
        .native => |native_info| blk: {
            if (native_info.type_id == CommandList.typeId(Buffer.VulkanCopyBufferNativeCommand)) {
                const buffer_copy_info = native_info.as(Buffer.VulkanCopyBufferNativeCommand);

                if (buffer_copy_info == null)
                    break :blk;
                
                const buffer_copy = adventvk.VkBufferCopy{
                    .size = buffer_copy_info.?.size,
                    .srcOffset = buffer_copy_info.?.src_offset,
                    .dstOffset = buffer_copy_info.?.dst_offset,
                };

                adventvk.vkCmdCopyBuffer(command_buffer, buffer_copy_info.?.src_buffer, buffer_copy_info.?.dst_buffer, 1, &buffer_copy);
            }
        }
    }
}

pub fn executeComputeQueue(self: *Device) !void {
    const command_buffer = self.primary_command_buffers[self.primary_command_buffer_index];
    self.primary_command_buffer_index = (self.primary_command_buffer_index + 1) % @as(u32, @intCast(self.primary_command_buffers.len));

    const begin_info = adventvk.VkCommandBufferBeginInfo{
        .sType = adventvk.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
    };

    var result = adventvk.vkBeginCommandBuffer(command_buffer, &begin_info);
    try VkResult.check(result);

    adventvk.vkCmdExecuteCommands(command_buffer, @intCast(self.submitted_command_buffers.items.len), self.submitted_command_buffers.items.ptr);

    result = adventvk.vkEndCommandBuffer(command_buffer);
    try VkResult.check(result);

    const wait_stages: []const u32 = &[_]u32 { adventvk.VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT };

    const submit_info = adventvk.VkSubmitInfo{
        .sType = adventvk.VK_STRUCTURE_TYPE_SUBMIT_INFO,
        .commandBufferCount = 1,
        .pCommandBuffers = &command_buffer,
        .waitSemaphoreCount = 1,
        .pWaitSemaphores = &self.semaphores[self.semaphore_index],
        .signalSemaphoreCount = 1,
        .pSignalSemaphores = &self.semaphores[(self.semaphore_index + self.semaphores.len - 1) % self.semaphores.len], // get previous semaphore,
        .pWaitDstStageMask = wait_stages.ptr,
    };

    result = adventvk.vkQueueSubmit(self.vk_data.queue, 1, &submit_info, self.fences[self.semaphore_index]);
    try VkResult.check(result);

    self.semaphore_index = (self.semaphore_index + 1) % @as(u32, @intCast(self.semaphores.len));

    self.submitted_command_buffers.clearRetainingCapacity();
}

pub fn waitForComputeQueue(self: *Device) !void {
    var result = adventvk.vkWaitForFences(self.vk_data.device, 1, &self.fences[(self.semaphore_index + self.semaphores.len - 1) % self.semaphores.len], adventvk.VK_TRUE, std.math.maxInt(u64));
    try VkResult.check(result);

    result = adventvk.vkResetFences(self.vk_data.device, 1, &self.fences[(self.semaphore_index + self.semaphores.len - 1) % self.semaphores.len]);
    try VkResult.check(result);
}

pub fn beginSingleTimeCommands(self: *Device) CommandList {
    var command_list = CommandList.init(self, true);
    command_list.begin();
    return command_list;
}

pub fn endSingleTimeCommands(self: *Device, command_list: *CommandList) !void {
    command_list.end();

    const alloc_info = adventvk.VkCommandBufferAllocateInfo{
        .sType = adventvk.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
        .commandPool = self.command_pool,
        .commandBufferCount = 1,
        .level = adventvk.VK_COMMAND_BUFFER_LEVEL_PRIMARY,
    };

    var command_buffer: adventvk.VkCommandBuffer = null;
    var result = adventvk.vkAllocateCommandBuffers(self.vk_data.device, &alloc_info, &command_buffer);
    try VkResult.check(result);

    const begin_info = adventvk.VkCommandBufferBeginInfo{
        .sType = adventvk.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
        .flags = adventvk.VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT,
    };

    result = adventvk.vkBeginCommandBuffer(command_buffer, &begin_info);
    try VkResult.check(result);
    
    for (command_list.getCommands()) |command| {
        executeCommand(command_buffer, &command);
    }

    result = adventvk.vkEndCommandBuffer(command_buffer);
    try VkResult.check(result);

    const submit_info = adventvk.VkSubmitInfo{
        .sType = adventvk.VK_STRUCTURE_TYPE_SUBMIT_INFO,
        .commandBufferCount = 1,
        .pCommandBuffers = &command_buffer,
    };

    result = adventvk.vkQueueSubmit(self.vk_data.queue, 1, &submit_info, null);
    try VkResult.check(result);

    result = adventvk.vkQueueWaitIdle(self.vk_data.queue);
    try VkResult.check(result);

    adventvk.vkFreeCommandBuffers(self.vk_data.device, self.command_pool, 1, &command_buffer);
}

fn toPipelineStage(stage: CommandList.ShaderStage) adventvk.VkPipelineStageFlags {
    var flags: adventvk.VkPipelineStageFlags = 0;
    if (stage.vertex) flags |= adventvk.VK_PIPELINE_STAGE_VERTEX_SHADER_BIT;
    if (stage.tess_control) flags |= adventvk.VK_PIPELINE_STAGE_TESSELLATION_CONTROL_SHADER_BIT;
    if (stage.tess_eval) flags |= adventvk.VK_PIPELINE_STAGE_TESSELLATION_EVALUATION_SHADER_BIT;
    if (stage.geometry) flags |= adventvk.VK_PIPELINE_STAGE_GEOMETRY_SHADER_BIT;
    if (stage.fragment) flags |= adventvk.VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT;
    if (stage.compute) flags |= adventvk.VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT;
    return if (flags != 0) flags else adventvk.VK_PIPELINE_STAGE_ALL_COMMANDS_BIT;
}
