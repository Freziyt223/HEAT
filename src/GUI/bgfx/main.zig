const std = @import("std");
const zbgfx = @import("zbgfx");
const glfw = @import("glfw");
const zgui = @import("zgui");
const TrackingAllocator = @import("TrackingAllocator");
const Interface = @import("Interface");
const Async = @import("Async");
pub var Allocator: TrackingAllocator = undefined;
const interface = Interface{
    .init = @ptrCast(&init),
};
const windowCtx = struct {};
pub export fn getInterface() Interface {
    return interface;
}
pub fn init(allocator: std.mem.Allocator) !void {
    Allocator = TrackingAllocator.init(allocator, "bgfxAllocator");
    try glfw.init();
    glfw.windowHint(.client_api, .no_api);
}
pub fn deinit() !void {
    glfw.terminate();
}

pub fn initWindow(window: *Interface.Window) !Interface.Renderer {
    const allocator = Allocator.allocator();
    const ctx = try allocator.create(windowCtx);
    return Interface.Renderer{
        .window = window,
        .renderer = interface,
        .ctx = @ptrCast(@alignCast(ctx)),
    };
}
pub fn deinitWindow(self: *Interface.Renderer) void {
    const allocator = Allocator.allocator();
    const ctx: *windowCtx = @ptrCast(@alignCast(self.ctx));
    allocator.destroy(ctx);
}
