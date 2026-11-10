const std = @import("std");
const Alignment = std.mem.Alignment;
const adventvk = @import("adventvk");

const Header = extern struct {
    size: usize,
    alignment: usize,
};

fn effAlign(a: usize) usize {
    return @max(a, @alignOf(Header));
}

fn prefixLen(al: usize) usize {
    return std.mem.alignForward(usize, @sizeOf(Header), al);
}

fn getAllocator(user: ?*anyopaque) std.mem.Allocator {
    const p: *const std.mem.Allocator = @ptrCast(@alignCast(user.?));
    return p.*;
}

fn header(user_ptr: [*]u8) *Header {
    return @ptrCast(@alignCast(user_ptr - @sizeOf(Header)));
}

fn vkAllocation(
    user: ?*anyopaque,
    size: usize,
    alignment: usize,
    scope: adventvk.VkSystemAllocationScope,
) callconv(.c) ?*anyopaque {
    _ = scope;
    if (size == 0) return null;
    const gpa = getAllocator(user);
    const al = effAlign(alignment);
    const prefix = prefixLen(al);
    const base = gpa.rawAlloc(prefix + size, Alignment.fromByteUnits(al), @returnAddress()) orelse
        return null; // never panic across the C boundary
    const user_ptr = base + prefix;
    header(user_ptr).* = .{ .size = size, .alignment = al };
    return user_ptr;
}

fn vkFree(user: ?*anyopaque, mem: ?*anyopaque) callconv(.c) void {
    const p = mem orelse return;
    const gpa = getAllocator(user);
    const user_ptr: [*]u8 = @ptrCast(p);
    const h = header(user_ptr).*;
    const prefix = prefixLen(h.alignment);
    const base = user_ptr - prefix;
    gpa.rawFree(base[0 .. prefix + h.size], Alignment.fromByteUnits(h.alignment), @returnAddress());
}

fn vkReallocation(
    user: ?*anyopaque,
    original: ?*anyopaque,
    size: usize,
    alignment: usize,
    scope: adventvk.VkSystemAllocationScope,
) callconv(.c) ?*anyopaque {
    const orig = original orelse return vkAllocation(user, size, alignment, scope);
    if (size == 0) {
        vkFree(user, orig);
        return null;
    }
    const old_ptr: [*]u8 = @ptrCast(orig);
    const old_size = header(old_ptr).size;
    // On failure, Vulkan requires the original allocation to be left untouched.
    const new = vkAllocation(user, size, alignment, scope) orelse return null;
    const new_ptr: [*]u8 = @ptrCast(new);
    const n = @min(size, old_size);
    @memcpy(new_ptr[0..n], old_ptr[0..n]);
    vkFree(user, orig);
    return new;
}

pub fn makeCallbacks(alloc_ptr: *const std.mem.Allocator) adventvk.VkAllocationCallbacks {
    return .{
        .pUserData = @constCast(@ptrCast(alloc_ptr)),
        .pfnAllocation = &vkAllocation,
        .pfnReallocation = &vkReallocation,
        .pfnFree = &vkFree,
        .pfnInternalAllocation = null,
        .pfnInternalFree = null,
    };
}
