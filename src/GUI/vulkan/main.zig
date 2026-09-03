const std = @import("std");
const vulkan = @import("vulkan");
const glfw = @import("glfw");
const TrackingAllocator = @import("TrackingAllocator");
pub var Allocator: TrackingAllocator = undefined;

pub fn init(alloc: std.mem.Allocator) !void {
    Allocator = TrackingAllocator.init("VulkanAllocator", alloc);
    try glfw.init();
    glfw.windowHint(.client_api, .no_api);
}
pub fn deinit() !void {}
