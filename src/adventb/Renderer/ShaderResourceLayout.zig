const std = @import("std");
const adventvk = @import("adventvk");

const Device = @import("Device.zig");

const VkResult = @import("VkResult.zig");
const shadergen = @import("shadergen");

const ShaderResourceLayout = @This();

device: *const Device,
set_layouts: std.ArrayList(adventvk.VkDescriptorSetLayout) = .empty,

pub fn init(self: *ShaderResourceLayout, device: *Device, layout_info: *const shadergen.ShaderResourceLayoutInfo) !void {
    self.* = .{ .device = device };
    
    for (layout_info.sets) |set| {
        var bindings = try device.allocator.alloc(adventvk.VkDescriptorSetLayoutBinding, set.resources.len);
        defer device.allocator.free(bindings);

        for (0..set.resources.len) |i| {
            const binding = adventvk.VkDescriptorSetLayoutBinding{
                .binding = set.resources[i].binding,
                .descriptorType = convertDescriptorType(set.resources[i].resource_type),
                .descriptorCount = set.resources[i].array_count,
                .stageFlags = @bitCast(set.resources[i].stage)
            };

            bindings[i] = binding;
        }

        const create_info = adventvk.VkDescriptorSetLayoutCreateInfo{
            .sType = adventvk.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
            .bindingCount = @intCast(bindings.len),
            .pBindings = @ptrCast(bindings.ptr)
        };

        var set_layout: adventvk.VkDescriptorSetLayout = undefined;
        const result = adventvk.vkCreateDescriptorSetLayout(device.vk_data.device, &create_info, device.vk_data.allocator, &set_layout);
        try VkResult.check(result);

        try self.set_layouts.append(device.allocator.*, set_layout);
        self.device = device;
    }
}

pub fn deinit(self: *ShaderResourceLayout) void {
    for (self.set_layouts.items) |set_layout| {
        adventvk.vkDestroyDescriptorSetLayout(self.device.vk_data.device, set_layout, self.device.vk_data.allocator);
    }

    self.set_layouts.deinit(self.device.allocator.*);
}

fn convertDescriptorType(resource_type: shadergen.ShaderResourceType) adventvk.VkDescriptorType {
    return switch (resource_type) {
        .uniform_buffer => adventvk.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
        .combined_image_sampler => adventvk.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
        .sampled_image => adventvk.VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE,
        .sampler => adventvk.VK_DESCRIPTOR_TYPE_SAMPLER,
        .storage_buffer => adventvk.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,
        .storage_image => adventvk.VK_DESCRIPTOR_TYPE_STORAGE_IMAGE,
    };
}
