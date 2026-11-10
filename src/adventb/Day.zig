const std = @import("std");

const Device = @import("Renderer/Device.zig");
const VkResult = @import("Renderer/VkResult.zig");

const Day = @This();

pub const DayVTable = struct {
    init: *const fn(context: *anyopaque, device: *Device) anyerror!void,
    run: *const fn(context: *anyopaque) anyerror![]const u8,
    deinit: *const fn(context: *anyopaque) void,
    get_name: *const fn() []const u8,
};

v_table: DayVTable,
context: *anyopaque,

pub fn asDay(day: anytype) Day {
    const Ptr = @TypeOf(day);
    const info = @typeInfo(Ptr);

    if (info != .pointer or info.pointer.size != .one)
        @compileError("expected a pointer, got " ++ @typeName(Ptr));

    const T = info.pointer.child;

    const gen = struct {
        fn init(context: *anyopaque, device: *Device) anyerror!void {
            const self: *T = @ptrCast(@alignCast(context));
            return T.init(self, device);
        }

        fn run(context: *anyopaque) anyerror![]const u8 {
            const self: *T = @ptrCast(@alignCast(context));
            return try T.run(self);
        }

        fn deinit(context: *anyopaque) void {
            const self: *T = @ptrCast(@alignCast(context));
            T.deinit(self);
        }

        fn getName() []const u8 {
            return T.getName();
        }
    };

    return .{
        .v_table = .{
            .init = gen.init,
            .run = gen.run,
            .deinit = gen.deinit,
            .get_name = gen.getName,
        },
        .context = day
    };
}

pub fn init(self: *const Day, device: *Device) !void {
    try self.v_table.init(self.context, device);
}

pub fn run(self: *const Day) ![]const u8 {
    return try self.v_table.run(self.context);
}

pub fn deinit(self: *const Day) void {
    self.v_table.deinit(self.context);
}

pub fn getName(self: *const Day) []const u8 {
    return self.v_table.get_name();
}
