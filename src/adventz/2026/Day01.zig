const std = @import("std");

const adventb = @import("adventb");
const TestDayShader = @import("../shaders/TestDay.slang.zig");

const Day01 = @This();

device: *adventb.Device,

pipeline: adventb.ComputePipeline = undefined,
shader_resource_layout: adventb.ShaderResourceLayout = undefined,
shader_resource: adventb.ShaderResource = undefined,

output_buffer: adventb.Buffer = undefined,
staging_buffer: adventb.Buffer = undefined,

command_list: adventb.CommandList = undefined,

allocations: std.ArrayList([]u8) = .empty, // a list of all allocations that happen in run(). all must be allocated with the align of a u8

pub fn init(self: *Day01, device: *adventb.Device) !void {
    self.device = device;

    try self.shader_resource_layout.init(device, &TestDayShader.TestDay.TestDay.resource_layout);
    errdefer self.shader_resource_layout.deinit();

    const pipeline_info = adventb.ComputePipeline.ComputePipelineInfo{
        .shader_spirv = TestDayShader.TestDay.spirv_code,
        .entry_point = TestDayShader.TestDay.TestDay.entry_point,
        .input_layout = TestDayShader.TestDay.TestDay.layout,
        .shader_resource_layout = &self.shader_resource_layout
    };

    try self.pipeline.init(device, &pipeline_info);
    errdefer self.pipeline.deinit();

    const data: [8]f32 = @splat(0.0);

    try self.output_buffer.initWithData(device, .{ .storage_buffer = true }, &data, data.len * @sizeOf(f32));
    errdefer self.output_buffer.deinit();

    try self.staging_buffer.init(device, .{ .staging_buffer = true }, data.len * @sizeOf(f32));
    errdefer self.staging_buffer.deinit();

    try self.shader_resource.init(device, 0, &self.shader_resource_layout);
    self.shader_resource.updateStorageBuffer(&self.output_buffer, 0, 0);

    self.command_list = adventb.CommandList.init(device, false);
    errdefer self.command_list.deinit();
}

pub fn run(self: *Day01) ![]const u8 {
    self.command_list.begin();

    try self.command_list.bindPipeline(&self.pipeline);
    try self.command_list.bindShaderResource(0, &self.shader_resource);
    try self.command_list.dispatch(1, 1, 1);

    try self.command_list.memoryBarrier(.{ .compute = true }, .{ .compute = true });

    try self.command_list.copyBuffer(&self.output_buffer, &self.staging_buffer, self.output_buffer.size, 0, 0);

    self.command_list.end();

    try self.device.submitCommandList(&self.command_list);
    try self.device.executeComputeQueue();
    try self.device.waitForComputeQueue();

    const result = try adventb.tools.extractFullArray(f32, &self.staging_buffer, self.device.allocator.*);
    defer self.device.allocator.free(result);

    const result_str = try self.device.allocator.print("{any}", .{ result });
    try self.allocations.append(self.device.allocator.*, result_str);

    return result_str;
}

pub fn deinit(self: *Day01) void {
    for (self.allocations.items) |alloc| {
        self.device.allocator.free(alloc);
    }
    self.allocations.deinit(self.device.allocator.*);

    self.command_list.deinit();
    self.staging_buffer.deinit();
    self.output_buffer.deinit();
    self.pipeline.deinit();
    self.shader_resource_layout.deinit();
}

pub fn getName() []const u8 {
    return "Day 1: Example day";
}
