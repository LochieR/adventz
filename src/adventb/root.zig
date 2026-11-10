pub const tools = @import("tools.zig");

pub const Day = @import("Day.zig");

pub const Device = @import("Renderer/Device.zig");
pub const Buffer = @import("Renderer/Buffer.zig");
pub const CommandList = @import("Renderer/CommandList.zig");
pub const ShaderResource = @import("Renderer/ShaderResource.zig");
pub const ComputePipeline = @import("Renderer/ComputePipeline.zig");
pub const ShaderResourceLayout = @import("Renderer/ShaderResourceLayout.zig");
pub const VkAllocator = @import("Renderer/VkAllocator.zig");
pub const VkResult = @import("Renderer/VkResult.zig");

/// Shared shader reflection types (same module the generated shader files use).
pub const shadergen = @import("shadergen");

test {
    refAllDeclsRecursive(@This());
}

/// Forces semantic analysis of every declaration in adventb (std only has the
/// non-recursive refAllDecls).
fn refAllDeclsRecursive(comptime T: type) void {
    inline for (comptime @import("std").meta.declarations(T)) |decl_name| {
        if (comptime T == @This() and @import("std").mem.eql(u8, decl_name, "shadergen")) continue;
        const D = @TypeOf(@field(T, decl_name));
        if (D == type) {
            const Inner = @field(T, decl_name);
            switch (@typeInfo(Inner)) {
                .@"struct", .@"enum", .@"union", .@"opaque" => refAllDeclsRecursive(Inner),
                else => {},
            }
        }
        _ = &@field(T, decl_name);
    }
}
