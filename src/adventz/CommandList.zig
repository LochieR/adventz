//! Backend-agnostic command recording. Commands are stored in a list and
//! translated to API calls (e.g. Vulkan) by the device at submit time.
//!
//! Only compute is supported for now: no render passes, graphics pipelines,
//! draws or image commands.
//!
//! Recorded commands hold plain pointers to pipelines, buffers and shader
//! resources. The caller must keep them alive until the command list has been
//! executed.

const std = @import("std");

const Buffer = @import("Buffer.zig");
const Device = @import("Device.zig");
const ComputePipeline = @import("ComputePipeline.zig");
const ShaderResource = @import("ShaderResource.zig");
const shadergen = @import("shaders/shadergen.zig");

const CommandList = @This();

pub const ShaderStage = shadergen.ShaderStage;

pub const max_push_constant_size = 128;

/// Bit layout matches VkAccessFlagBits, so it can be @bitCast directly.
pub const BarrierMask = packed struct(u32) {
    _reserved0: u5 = 0,
    shader_read: bool = false,
    shader_write: bool = false,
    color_attachment_read: bool = false,
    color_attachment_write: bool = false,
    depth_stencil_attachment_read: bool = false,
    depth_stencil_attachment_write: bool = false,
    transfer_read: bool = false,
    transfer_write: bool = false,
    _reserved1: u19 = 0,
};

/// Bit layout matches VkPipelineStageFlagBits, so it can be @bitCast directly.
pub const PipelineStage = packed struct(u32) {
    top_of_pipe: bool = false,
    draw_indirect: bool = false,
    vertex_input: bool = false,
    vertex_shader: bool = false,
    _reserved0: u3 = 0,
    fragment_shader: bool = false,
    early_fragment_tests: bool = false,
    late_fragment_tests: bool = false,
    color_attachment_output: bool = false,
    compute_shader: bool = false,
    transfer: bool = false,
    _reserved1: u19 = 0,
};

/// Opaque identity for a native command's type. See `typeId`.
pub const TypeId = *const anyopaque;

/// Returns a unique id for `T`, used to tag native commands (the Zig
/// equivalent of std::type_index).
pub fn typeId(comptime T: type) TypeId {
    const Marker = struct {
        const Type = T;
        var byte: u8 = 0;
    };
    return &Marker.byte;
}

pub const Command = union(enum) {
    bind_pipeline: BindPipeline,
    push_constants: PushConstants,
    bind_shader_resource: BindShaderResource,
    dispatch: Dispatch,
    copy_buffer: CopyBuffer,
    buffer_memory_barrier: BufferMemoryBarrier,
    memory_barrier: MemoryBarrier,
    native: Native,

    pub const BindPipeline = struct {
        pipeline: *const ComputePipeline,
    };

    pub const PushConstants = struct {
        pipeline: *const ComputePipeline,
        stage: ShaderStage,
        size: u32,
        offset: u32,
        data: [max_push_constant_size]u8,

        pub fn bytes(self: *const PushConstants) []const u8 {
            return self.data[0..self.size];
        }
    };

    pub const BindShaderResource = struct {
        pipeline: *const ComputePipeline,
        set: u32,
        resource: *const ShaderResource,
    };

    pub const Dispatch = struct {
        group_count_x: u32,
        group_count_y: u32,
        group_count_z: u32,
    };

    pub const CopyBuffer = struct {
        src_buffer: *const Buffer,
        dst_buffer: *const Buffer,
        size: usize,
        src_offset: usize,
        dst_offset: usize,
    };

    pub const BufferMemoryBarrier = struct {
        wait_for: BarrierMask,
        access: BarrierMask,
        wait_stage: PipelineStage,
        until_stage: PipelineStage,
        buffer: *const Buffer,
    };

    pub const MemoryBarrier = struct {
        from: ShaderStage,
        to: ShaderStage,
    };

    /// A backend-specific command. `type_id` identifies the type that `ptr`
    /// points to. Use `as` to get it back as that type.
    pub const Native = struct {
        type_id: TypeId,
        ptr: *anyopaque,

        pub fn as(self: Native, comptime T: type) ?*T {
            if (self.type_id != typeId(T)) return null;
            return @ptrCast(@alignCast(self.ptr));
        }
    };
};

device: *Device,
single_time_commands: bool,
is_recording: bool = false,

commands: std.ArrayList(Command) = .empty,
current_compute_pipeline: ?*const ComputePipeline = null,

pub fn init(device: *Device, single_time_commands: bool) CommandList {
    return .{
        .device = device,
        .single_time_commands = single_time_commands,
    };
}

pub fn deinit(self: *CommandList) void {
    self.commands.deinit(self.device.allocator.*);
}

pub fn begin(self: *CommandList) void {
    self.commands.clearRetainingCapacity();
    self.current_compute_pipeline = null;
    self.is_recording = true;
}

pub fn end(self: *CommandList) void {
    self.is_recording = false;
    self.current_compute_pipeline = null;
}

pub fn bindPipeline(self: *CommandList, pipeline: *const ComputePipeline) !void {
    self.current_compute_pipeline = pipeline;
    try self.record(.{ .bind_pipeline = .{ .pipeline = pipeline } });
}

pub fn pushConstants(self: *CommandList, shader_stage: ShaderStage, data: []const u8, offset: usize) !void {
    const pipeline = self.current_compute_pipeline orelse
        fail("cannot push constants without binding a pipeline");
    check(data.len <= max_push_constant_size, "push constant size must be <= 128");

    var args = Command.PushConstants{
        .pipeline = pipeline,
        .stage = shader_stage,
        .size = @intCast(data.len),
        .offset = @intCast(offset),
        .data = undefined,
    };
    @memcpy(args.data[0..data.len], data);

    try self.record(.{ .push_constants = args });
}

/// Pushes `value` as raw bytes (the equivalent of the templated C++ overload).
pub fn pushConstantsValue(self: *CommandList, shader_stage: ShaderStage, value: anytype, offset: usize) !void {
    try self.pushConstants(shader_stage, std.mem.asBytes(&value), offset);
}

pub fn bindShaderResource(self: *CommandList, set: u32, resource: *const ShaderResource) !void {
    const pipeline = self.current_compute_pipeline orelse
        fail("cannot bind descriptor set without binding a pipeline");

    try self.record(.{ .bind_shader_resource = .{
        .pipeline = pipeline,
        .set = set,
        .resource = resource,
    } });
}

pub fn dispatch(self: *CommandList, group_count_x: u32, group_count_y: u32, group_count_z: u32) !void {
    check(self.current_compute_pipeline != null, "cannot dispatch without binding compute pipeline");

    try self.record(.{ .dispatch = .{
        .group_count_x = group_count_x,
        .group_count_y = group_count_y,
        .group_count_z = group_count_z,
    } });
}

pub fn copyBuffer(self: *CommandList, src_buffer: *const Buffer, dst_buffer: *const Buffer, size: usize, src_offset: usize, dst_offset: usize) !void {
    try self.record(.{ .copy_buffer = .{
        .src_buffer = src_buffer,
        .dst_buffer = dst_buffer,
        .size = size,
        .src_offset = src_offset,
        .dst_offset = dst_offset,
    } });
}

pub fn bufferMemoryBarrier(self: *CommandList, buffer: *const Buffer, wait_for: BarrierMask, access: BarrierMask, wait_stage: PipelineStage, until_stage: PipelineStage) !void {
    try self.record(.{ .buffer_memory_barrier = .{
        .wait_for = wait_for,
        .access = access,
        .wait_stage = wait_stage,
        .until_stage = until_stage,
        .buffer = buffer,
    } });
}

pub fn memoryBarrier(self: *CommandList, from: ShaderStage, to: ShaderStage) !void {
    try self.record(.{ .memory_barrier = .{ .from = from, .to = to } });
}

/// Records a backend-specific command. `native_command` must outlive the
/// command list's execution.
pub fn submitNativeCommand(self: *CommandList, comptime T: type, native_command: *T) !void {
    try self.record(.{ .native = .{
        .type_id = typeId(T),
        .ptr = native_command,
    } });
}

pub fn getCommands(self: *const CommandList) []const Command {
    return self.commands.items;
}

fn record(self: *CommandList, command: Command) !void {
    check(self.is_recording, "command list is not recording; call begin() first");
    try self.commands.append(self.device.allocator.*, command);
}

fn check(ok: bool, comptime msg: []const u8) void {
    if (std.debug.runtime_safety and !ok) @panic(msg);
}

fn fail(comptime msg: []const u8) noreturn {
    @panic(msg);
}
