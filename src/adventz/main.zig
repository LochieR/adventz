const std = @import("std");
const builtin = @import("builtin");

const Buffer = @import("Buffer.zig");
const Device = @import("Device.zig");
const CommandList = @import("CommandList.zig");
const ComputePipeline = @import("ComputePipeline.zig");
const ShaderResource = @import("ShaderResource.zig");
const ShaderResourceLayout = @import("ShaderResourceLayout.zig");

const VkAllocator = @import("VkAllocator.zig");

const adventvk = @import("adventvk");

const TestDayShader = @import("shaders/TestDay.slang.zig");

pub fn main() !void {
    var safe_allocator = std.heap.SafeAllocator.init(std.heap.page_allocator, .{});
    defer _ = safe_allocator.deinit();
    
    var allocator: std.mem.Allocator = undefined;
    if (builtin.optimize == .debug) {
        allocator = safe_allocator.allocator();
    } else {
        allocator = std.heap.c_allocator;
    }

    var device: Device = undefined;
    try device.init(&allocator);
    defer device.deinit();

    var shader_resource_layout: ShaderResourceLayout = undefined;
    try shader_resource_layout.init(&device, &TestDayShader.TestDay.TestDay.resource_layout);
    defer shader_resource_layout.deinit();

    const pipeline_info = ComputePipeline.ComputePipelineInfo{
        .shader_spirv = TestDayShader.TestDay.spirv_code,
        .entry_point = TestDayShader.TestDay.TestDay.entry_point,
        .input_layout = TestDayShader.TestDay.TestDay.layout,
        .shader_resource_layout = &shader_resource_layout
    };

    var pipeline: ComputePipeline = undefined;
    try pipeline.init(&device, &pipeline_info);
    defer pipeline.deinit();

    const data = [_]f32 {
        0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
    };

    var output_buffer: Buffer = undefined;
    try output_buffer.initWithData(&device, .{ .storage_buffer = true }, &data, data.len * @sizeOf(f32));
    defer output_buffer.deinit();

    var staging_buffer: Buffer = undefined;
    try staging_buffer.init(&device, .{ .staging_buffer = true }, data.len * @sizeOf(f32));
    defer staging_buffer.deinit();

    var shader_resource: ShaderResource = undefined;
    try shader_resource.init(&device, 0, &shader_resource_layout);

    shader_resource.updateStorageBuffer(&output_buffer, 0, 0);

    var command_list = CommandList.init(&device, false);
    command_list.begin();

    try command_list.bindPipeline(&pipeline);
    try command_list.bindShaderResource(0, &shader_resource);
    try command_list.dispatch(1, 1, 1);

    try command_list.memoryBarrier(.{ .compute = true }, .{ .compute = true });

    try command_list.copyBuffer(&output_buffer, &staging_buffer, output_buffer.size, 0, 0);

    command_list.end();

    try device.submitCommandList(&command_list);
    try device.executeComputeQueue();
    try device.waitForComputeQueue();

    const result = try allocator.alloc(u8, staging_buffer.size);
    const memory: ?[*]u8 = @ptrCast(try staging_buffer.map(staging_buffer.size));
    @memcpy(result, memory.?[0..staging_buffer.size]);
    try staging_buffer.unmap();

    const result_floats: []f32 = @as([*]f32, @alignCast(@ptrCast(result.ptr)))[0..data.len];

    std.debug.print("{any}\n", .{ result_floats });

    allocator.free(result);

    command_list.deinit();
}
