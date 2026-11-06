const std = @import("std");
const adventvk = @import("adventvk");

const shadergen = @import("shaders/shadergen.zig");

const Device = @import("Device.zig");
const ShaderResourceLayout = @import("ShaderResourceLayout.zig");

const VkResult = @import("VkResult.zig");
const ComputePipeline = @This();

pub const ComputePipelineInfo = struct {
    shader_spirv: []const u32,
    entry_point: shadergen.ShaderEntryPoint,
    input_layout: shadergen.ComputeInputLayout,
    shader_resource_layout: ?*const ShaderResourceLayout,
};

device: *const Device = undefined,
shader_module: adventvk.VkShaderModule = undefined,
pipeline_layout: adventvk.VkPipelineLayout = undefined,
pipeline: adventvk.VkPipeline = undefined,

pub fn init(self: *ComputePipeline, device: *Device, pipeline_info: *const ComputePipelineInfo) !void {
    const module_info = adventvk.VkShaderModuleCreateInfo{
        .sType = adventvk.VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
        .codeSize = pipeline_info.shader_spirv.len * @sizeOf(u32),
        .pCode = @ptrCast(pipeline_info.shader_spirv.ptr),
    };

    var result = adventvk.vkCreateShaderModule(device.vk_data.device.?, @ptrCast(&module_info), device.vk_data.allocator, &self.shader_module);
    try VkResult.check(result);

    const compute_stage_info = adventvk.VkPipelineShaderStageCreateInfo{
        .sType = adventvk.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
        .stage = adventvk.VK_SHADER_STAGE_COMPUTE_BIT,
        .module = self.shader_module,
        .pName = pipeline_info.entry_point.name.ptr,
    };

    var push_constant_ranges = try device.allocator.alloc(adventvk.VkPushConstantRange, pipeline_info.input_layout.push_constants.len);
    defer device.allocator.free(push_constant_ranges);
    for (0..push_constant_ranges.len) |i| {
        push_constant_ranges[i].size = @intCast(pipeline_info.input_layout.push_constants[i].size);
        push_constant_ranges[i].offset = @intCast(pipeline_info.input_layout.push_constants[i].offset);
        push_constant_ranges[i].stageFlags = @bitCast(pipeline_info.input_layout.push_constants[i].shader);
    }

    const pipeline_layout_info = adventvk.VkPipelineLayoutCreateInfo{
        .sType = adventvk.VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
        .setLayoutCount = if (pipeline_info.shader_resource_layout) |l| @intCast(l.set_layouts.items.len) else 0,
        .pSetLayouts = if (pipeline_info.shader_resource_layout) |l| @ptrCast(l.set_layouts.items.ptr) else null,
        .pushConstantRangeCount = @intCast(push_constant_ranges.len),
        .pPushConstantRanges = if (push_constant_ranges.len == 0) null else @ptrCast(push_constant_ranges.ptr),
    };

    result = adventvk.vkCreatePipelineLayout(device.vk_data.device, &pipeline_layout_info, device.vk_data.allocator, &self.pipeline_layout);
    try VkResult.check(result);

    const create_info = adventvk.VkComputePipelineCreateInfo{
        .sType = adventvk.VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO,
        .layout = self.pipeline_layout,
        .stage = compute_stage_info
    };

    result = adventvk.vkCreateComputePipelines(device.vk_data.device, null, 1, @ptrCast(&create_info), device.vk_data.allocator, &self.pipeline);
    try VkResult.check(result);

    self.device = device;
}

pub fn deinit(self: *ComputePipeline) void {
    adventvk.vkDestroyPipeline(self.device.vk_data.device, self.pipeline, self.device.vk_data.allocator);
    adventvk.vkDestroyPipelineLayout(self.device.vk_data.device, self.pipeline_layout, self.device.vk_data.allocator);
    adventvk.vkDestroyShaderModule(self.device.vk_data.device, self.shader_module, self.device.vk_data.allocator);
}
