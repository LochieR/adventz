const std = @import("std");

const Buffer = @import("Renderer/Buffer.zig");
const ComputePipeline = @import("Renderer/ComputePipeline.zig");
const ShaderResourceLayout = @import("Renderer/ShaderResourceLayout.zig");

pub const TypeId = *const anyopaque;

pub fn typeId(comptime T: type) TypeId {
    const Marker = struct {
        const Type = T;
        var byte: u8 = 0;
    };
    return &Marker.byte;
}

pub fn extractFullArray(comptime T: type, staging_buffer: *const Buffer, allocator: std.mem.Allocator) ![]T {
    if (!staging_buffer.buffer_type.staging_buffer) {
        return error.IncorrectBufferType;
    }

    const data_length: usize = staging_buffer.size / @sizeOf(T);
    const result = try allocator.alloc(T, data_length);
    errdefer allocator.free(result);

    const result_bytes = std.mem.sliceAsBytes(result);
    const memory: ?[*]u8 = @ptrCast(try staging_buffer.map(staging_buffer.size));
    @memcpy(result_bytes, memory.?[0..result_bytes.len]);
    try staging_buffer.unmap();

    return result;
}
