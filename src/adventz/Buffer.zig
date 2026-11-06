const std = @import("std");
const adventvk = @import("adventvk");

const Device = @import("Device.zig");
const Buffer = @This();

const VkResult = @import("VkResult.zig");

const BufferType = packed struct(u8) {
    vertex_buffer: bool = false,
    index_buffer: bool = false,
    staging_buffer: bool = false,
    uniform_buffer: bool = false,
    storage_buffer: bool = false,
    _padding: u3 = 0,
};

device: *Device = undefined,
buffer: adventvk.VkBuffer = null,
memory: adventvk.VkDeviceMemory = null,
size: usize = 0,
staging_buffer: adventvk.VkBuffer = null,
staging_memory: adventvk.VkDeviceMemory = null,
buffer_type: BufferType = undefined,

pub fn init(self: *Buffer, device: *Device, buffer_type: BufferType, size: usize) !void {
    self.device = device;
    self.buffer_type = buffer_type;
    self.size = size;

    try createBuffer(
        device.vk_data.device,
        device.vk_data.physical_device,
        device.vk_data.allocator,
        size,
        getBufferUsage(buffer_type),
        getBufferMemoryProperties(buffer_type),
        &self.buffer,
        &self.memory
    );

    if (needStagingBuffer(buffer_type)) {
        try createBuffer(
            device.vk_data.device,
            device.vk_data.physical_device,
            device.vk_data.allocator,
            size,
            adventvk.VK_BUFFER_USAGE_TRANSFER_SRC_BIT,
            adventvk.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | adventvk.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
            &self.staging_buffer,
            &self.staging_memory
        );
    }
}

pub fn initWithData(self: *Buffer, device: *Device, buffer_type: BufferType, data: *const anyopaque, size: usize) !void {
    self.device = device;
    self.buffer_type = buffer_type;
    self.size = size;

    try createBuffer(
        device.vk_data.device,
        device.vk_data.physical_device,
        device.vk_data.allocator,
        size,
        getBufferUsage(buffer_type),
        getBufferMemoryProperties(buffer_type),
        &self.buffer,
        &self.memory
    );

    if (needStagingBuffer(buffer_type)) {
        try createBuffer(
            device.vk_data.device,
            device.vk_data.physical_device,
            device.vk_data.allocator,
            size,
            adventvk.VK_BUFFER_USAGE_TRANSFER_SRC_BIT,
            adventvk.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | adventvk.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
            &self.staging_buffer,
            &self.staging_memory
        );
    }

    const memory = try self.map(size);

    const dst: [*]u8 = @ptrCast(memory);
    const src: [*]const u8 = @ptrCast(data);

    @memcpy(dst[0..size], src[0..size]);
    try self.unmap();
}

pub fn deinit(self: *Buffer) void {
    if (needStagingBuffer(self.buffer_type)) {
        adventvk.vkDestroyBuffer(self.device.vk_data.device, self.staging_buffer, self.device.vk_data.allocator);
        adventvk.vkFreeMemory(self.device.vk_data.device, self.staging_memory, self.device.vk_data.allocator);
    }
    adventvk.vkDestroyBuffer(self.device.vk_data.device, self.buffer, self.device.vk_data.allocator);
    adventvk.vkFreeMemory(self.device.vk_data.device, self.memory, self.device.vk_data.allocator);
}

pub fn map(self: *Buffer, size: usize) !?*anyopaque {
    if (needStagingBuffer(self.buffer_type)) {
        var memory: ?*anyopaque = null;
        const result = adventvk.vkMapMemory(self.device.vk_data.device, self.staging_memory, 0, size, 0, &memory);
        try VkResult.check(result);
        return memory;
    } else {
        var memory: ?*anyopaque = null;
        const result = adventvk.vkMapMemory(self.device.vk_data.device, self.memory, 0, size, 0, &memory);
        try VkResult.check(result);
        return memory;
    }
}

pub const VulkanCopyBufferNativeCommand = struct {
    src_buffer: adventvk.VkBuffer,
    dst_buffer: adventvk.VkBuffer,
    size: usize,
    src_offset: usize,
    dst_offset: usize,
};

pub fn unmap(self: *Buffer) !void {
    if (needStagingBuffer(self.buffer_type)) {
        adventvk.vkUnmapMemory(self.device.vk_data.device, self.staging_memory);

        var buffer_copy = VulkanCopyBufferNativeCommand{
            .src_buffer = self.staging_buffer,
            .dst_buffer = self.buffer,
            .size = self.size,
            .src_offset = 0,
            .dst_offset = 0,
        };

        var command_list = self.device.beginSingleTimeCommands();
        try command_list.submitNativeCommand(VulkanCopyBufferNativeCommand, &buffer_copy);
        try self.device.endSingleTimeCommands(&command_list);

        command_list.deinit();
    } else {
        adventvk.vkUnmapMemory(self.device.vk_data.device, self.memory);
    }
}

fn createBuffer(device: adventvk.VkDevice, physical_device: adventvk.VkPhysicalDevice, allocator: *const adventvk.VkAllocationCallbacks, size: usize, usage: adventvk.VkBufferUsageFlags, properties: adventvk.VkMemoryPropertyFlags, buffer: *adventvk.VkBuffer, memory: *adventvk.VkDeviceMemory) !void {
    const buffer_info = adventvk.VkBufferCreateInfo{
        .sType = adventvk.VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
        .queueFamilyIndexCount = 0,
        .pQueueFamilyIndices = null,
        .sharingMode = adventvk.VK_SHARING_MODE_EXCLUSIVE,
        .size = size,
        .usage = usage,
    };

    var result = adventvk.vkCreateBuffer(device, &buffer_info, allocator, buffer);
    try VkResult.check(result);

    var mem_requirements: adventvk.VkMemoryRequirements = undefined;
    adventvk.vkGetBufferMemoryRequirements(device, buffer.*, &mem_requirements);

    const alloc_info = adventvk.VkMemoryAllocateInfo{
        .sType = adventvk.VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
        .allocationSize = mem_requirements.size,
        .memoryTypeIndex = try findMemoryType(physical_device, mem_requirements.memoryTypeBits, properties)
    };

    result = adventvk.vkAllocateMemory(device, &alloc_info, allocator, memory);
    try VkResult.check(result);

    result = adventvk.vkBindBufferMemory(device, buffer.*, memory.*, 0);
    try VkResult.check(result);
}

fn findMemoryType(physical_device: adventvk.VkPhysicalDevice, type_filter: u32, properties: adventvk.VkMemoryPropertyFlags) !u32 {
    var mem_properties: adventvk.VkPhysicalDeviceMemoryProperties = undefined;
    adventvk.vkGetPhysicalDeviceMemoryProperties(physical_device, &mem_properties);

    for(0..mem_properties.memoryTypeCount) |i| {
        if ((type_filter & (@as(u32, 1) << @as(u5, @intCast(i)))) != 0 and (mem_properties.memoryTypes[i].propertyFlags & properties) == properties) {
            return @intCast(i);
        }
    }

    return error.NoSuitableMemoryType;
}

fn getBufferMemoryProperties(buffer_type: BufferType) adventvk.VkMemoryPropertyFlags {
    var flags: adventvk.VkMemoryPropertyFlags = 0;

    if (needStagingBuffer(buffer_type)) {
        flags = adventvk.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT;
    } else {
        flags = adventvk.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | adventvk.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT;
    }

    return flags;
}

fn needStagingBuffer(buffer_type: BufferType) bool {
    return buffer_type.index_buffer or buffer_type.storage_buffer;
}

fn getBufferUsage(buffer_type: BufferType) adventvk.VkBufferUsageFlags {
    var usage: u32 = 0;

    if (buffer_type.vertex_buffer) {
        usage |= adventvk.VK_BUFFER_USAGE_VERTEX_BUFFER_BIT;
    }
    if (buffer_type.index_buffer) {
        usage |= adventvk.VK_BUFFER_USAGE_TRANSFER_DST_BIT | adventvk.VK_BUFFER_USAGE_INDEX_BUFFER_BIT;
    }
    if (buffer_type.staging_buffer) {
        usage |= adventvk.VK_BUFFER_USAGE_TRANSFER_SRC_BIT | adventvk.VK_BUFFER_USAGE_TRANSFER_DST_BIT;
    }
    if (buffer_type.uniform_buffer) {
        usage |= adventvk.VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT;
    }
    if (buffer_type.storage_buffer) {
        usage |= adventvk.VK_BUFFER_USAGE_TRANSFER_SRC_BIT | adventvk.VK_BUFFER_USAGE_TRANSFER_DST_BIT | adventvk.VK_BUFFER_USAGE_STORAGE_BUFFER_BIT;
    }

    return usage;
}
