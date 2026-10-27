const std = @import("std");
const Interface = @import("Interface");
const host = @import("host.zig");
const context = @import("context.zig");
const frame = @import("frame.zig");
const resources = @import("resources.zig");

const interface = Interface{
    .init = @ptrCast(&init),
    .deinit = &deinit,
    .initWindow = @ptrCast(&initWindow),
    .deinitWindow = &deinitWindow,
    .switchPhysicalDevice = @ptrCast(&switchPhysicalDevice),
    .enumeratePhysicalDevices = @ptrCast(&enumeratePhysicalDevices),
    .getPhysicalDevice = &getPhysicalDevice,
    .beginFrame = @ptrCast(&frame.beginFrame),
    .clear = @ptrCast(&frame.clear),
    .bindPipeline = @ptrCast(&frame.bindPipeline),
    .draw = @ptrCast(&frame.draw),
    .endFrame = @ptrCast(&frame.endFrame),
    .present = @ptrCast(&frame.present),
    .createShaderModule = @ptrCast(&resources.createShaderModule),
    .destroyShaderModule = &resources.destroyShaderModule,
    .createGraphicsPipeline = @ptrCast(&resources.createGraphicsPipeline),
    .destroyGraphicsPipeline = &resources.destroyGraphicsPipeline,
    .createVertexBuffer = @ptrCast(&resources.createVertexBuffer),
    .destroyVertexBuffer = &resources.destroyVertexBuffer,
    .bindVertexBuffer = @ptrCast(&resources.bindVertexBuffer),
    .createIndexBuffer = @ptrCast(&resources.createIndexBuffer),
    .destroyIndexBuffer = &resources.destroyIndexBuffer,
    .bindIndexBuffer = @ptrCast(&resources.bindIndexBuffer),
    .createDescriptorSetLayout = @ptrCast(&resources.createDescriptorSetLayout),
    .destroyDescriptorSetLayout = &resources.destroyDescriptorSetLayout,
    .createDescriptorPool = @ptrCast(&resources.createDescriptorPool),
    .destroyDescriptorPool = &resources.destroyDescriptorPool,
    .allocateDescriptorSets = @ptrCast(&resources.allocateDescriptorSets),
    .freeDescriptorSets = @ptrCast(&resources.freeDescriptorSets),
    .bindDescriptorSets = @ptrCast(&resources.bindDescriptorSets),
};

pub fn getInterface() Interface {
    return interface;
}

pub fn init(_: std.mem.Allocator) !void {
    context.context.frame_state.store(.idle, .release);
    host.canvas_init(960, 600);
}
pub fn deinit() void {
    host.canvas_deinit();
}

pub fn initWindow(renderer: Interface, window: *Interface.Window, _: u32) !Interface.Renderer {
    return .{
        .window = window,
        .renderer = renderer,
        .ctx = @ptrCast(&context.context),
    };
}
pub fn deinitWindow(_: Interface.Renderer) void {}

pub fn switchPhysicalDevice(_: Interface.DeviceSelection, _: *Interface.DeviceInfo) !void {}
pub fn enumeratePhysicalDevices(allocator: std.mem.Allocator) ![]Interface.DeviceInfo {
    return allocator.alloc(Interface.DeviceInfo, 0);
}
pub fn getPhysicalDevice() Interface.DeviceInfo {
    return .{ .index = 0, .name = .{0} ** 256, .type = .cpu };
}
