const std = @import("std");
const builtin = @import("builtin");
const adventb = @import("adventb");

const Gui = @import("Gui.zig");

const Buffer = adventb.Buffer;
const Device = adventb.Device;
const CommandList = adventb.CommandList;
const ComputePipeline = adventb.ComputePipeline;
const ShaderResource = adventb.ShaderResource;
const ShaderResourceLayout = adventb.ShaderResourceLayout;

const Y2026 = @import("2026/2026.zig");

const Day01 = @import("2026/Day01.zig");
const TestDayShader = @import("shaders/TestDay.slang.zig");

pub fn main(init: std.process.Init) !void {
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

    for (Y2026.days) |day| {
        try day.init(&device);
    }

    defer for (Y2026.days) |day| {
        day.deinit();
    };

    var gui: Gui = undefined;
    try gui.init(init, &allocator);
    defer gui.deinit();

    try gui.run();
}
