//! For now only uses vulkan with glfw and no interface
const std = @import("std");
const vulkan = @import("vulkan");
const TrackingAllocator = @import("TrackingAllocator");
pub var Allocator: TrackingAllocator = undefined;

pub fn init(allocator: std.mem.Allocator) !void {
    Allocator = TrackingAllocator.init("GUIAllocator", allocator);
    vulkan.init(Allocator.allocator());
}
pub fn deinit() !void {
    vulkan.deinit();
}
