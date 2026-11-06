const std = @import("std");
const adventvk = @import("adventvk");

const Device = @import("Device.zig");
const Buffer = @import("Buffer.zig");
const ShaderResourceLayout = @import("ShaderResourceLayout.zig");

const VkResult = @import("VkResult.zig");

const ShaderResource = @This();

device: *const Device = undefined,
layout: *const ShaderResourceLayout = undefined,
set: adventvk.VkDescriptorSet = null,

pub fn init(self: *ShaderResource, device: *Device, set: u32, shader_resource_layout: *const ShaderResourceLayout) !void {
    self.device = device;
    self.layout = shader_resource_layout;

    const alloc_info = adventvk.VkDescriptorSetAllocateInfo{
        .sType = adventvk.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
        .descriptorPool = device.descriptor_pool,
        .descriptorSetCount = 1,
        .pSetLayouts = &shader_resource_layout.set_layouts.items[set]
    };

    const result = adventvk.vkAllocateDescriptorSets(device.vk_data.device, &alloc_info, &self.set);
    try VkResult.check(result);
}

pub fn updateStorageBuffer(self: *ShaderResource, storage_buffer: *const Buffer, binding: u32, index: u32) void {
    const buffer_info = adventvk.VkDescriptorBufferInfo{
        .buffer = storage_buffer.buffer,
        .range = storage_buffer.size,
        .offset = 0
    };

    const descriptor_write = adventvk.VkWriteDescriptorSet{
        .sType = adventvk.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
        .dstSet = self.set,
        .dstBinding = binding,
        .dstArrayElement = index,
        .descriptorType = adventvk.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,
        .descriptorCount = 1,
        .pBufferInfo = &buffer_info,
    };

    adventvk.vkUpdateDescriptorSets(self.device.vk_data.device, 1, &descriptor_write, 0, null);
}
