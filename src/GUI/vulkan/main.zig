const std = @import("std");
const vulkan = @import("vulkan");
const glfw = @import("glfw");
const zgui = @import("zgui");
const zgui_backend = @import("zgui_backend");
const TrackingAllocator = @import("TrackingAllocator");
const Interface = @import("Interface");
const Async = @import("Async");
const GraphicsContext = @import("self.zig");
var global_ctx: GraphicsContext.GraphicsContex = undefined;
pub var Allocator: TrackingAllocator = undefined;

const interface = Interface{
    .init = @ptrCast(&init),
    .deinit = &deinit,
    .initWindow = @ptrCast(&initWindow),
    .deinitWindow = &deinitWindow,
    .switchPhysicalDevice = @ptrCast(&switchPhysicalDevice),
    .enumeratePhysicalDevices = @ptrCast(&enumeratePhysicalDevices),
    .getPhysicalDevice = &getPhysicalDevice,
    .beginFrame = @ptrCast(&beginFrame),
    .bindPipeline = @ptrCast(&bindPipeline),
    .draw = @ptrCast(&draw),
    .endFrame = @ptrCast(&endFrame),
    .present = @ptrCast(&present),
    .createShaderModule = @ptrCast(&createShaderModule),
    .destroyShaderModule = @ptrCast(&destroyShaderModule),
    .createGraphicsPipeline = @ptrCast(&createGraphicsPipeline),
    .destroyGraphicsPipeline = @ptrCast(&destroyGraphicsPipeline),
};

pub fn getInterface() Interface {
    return interface;
}

pub fn init(allocator: std.mem.Allocator) anyerror!void {
    try try Async.callMainSync(internal_init, .{allocator});
}
fn internal_init(allocator: std.mem.Allocator) !void {
    std.debug.print("Hi!", .{});
    Allocator = TrackingAllocator.init(allocator, "VulkanAllocator");
    try glfw.init();
    if (!glfw.isVulkanSupported()) {
        std.debug.print("GLFW couldn't find libvulkan\n", .{});
        return error.NoVulkan;
    }
    glfw.windowHint(.client_api, .no_api);
    glfw.windowHint(.visible, true);

    // Ініціалізація глобального контексту Vulkan (Instance, Debug, etc.)
    global_ctx = try GraphicsContext.GraphicsContex.init(Allocator.allocator());
}
pub fn deinit() void {
    std.debug.print("Vulkan deinit START\n", .{});

    global_ctx.deinit();

    std.debug.print("Vulkan deinit END\n", .{});

    glfw.terminate();
}

pub fn initWindow(renderer: Interface, window: *Interface.Window, queue_index: u32) !Interface.Renderer {
    glfw.windowHint(.client_api, .no_api);
    glfw.windowHint(.visible, true);
    const window_ctx = try try Async.callMainSync(
        GraphicsContext.WindowContext.init,
        .{
            Allocator.allocator(),
            &global_ctx,
            window,
            queue_index,
        },
    );

    return Interface.Renderer{
        .window = window,
        .renderer = renderer,
        .ctx = @ptrCast(window_ctx),
    };
}

pub fn deinitWindow(self: Interface.Renderer) void {
    const window_ctx: *GraphicsContext.WindowContext = @ptrCast(@alignCast(self.ctx));
    window_ctx.deinit(&global_ctx);
}

pub fn switchPhysicalDevice(selection: Interface.DeviceSelection, device: *Interface.DeviceInfo) !void {
    try global_ctx.selectPhysicalDevice(selection);
    device.* = try global_ctx.getPhysicalDevice();
}

pub fn enumeratePhysicalDevices(allocator: std.mem.Allocator) ![]Interface.DeviceInfo {
    return global_ctx.enumeratePhysicalDevices(allocator);
}
pub fn getPhysicalDevice() Interface.DeviceInfo {
    return global_ctx.getPhysicalDevice() catch unreachable;
}

fn createShaderModule(ctx: *anyopaque, spirv: []const u8) !Interface.Renderer.ShaderModule {
    const window_ctx: *GraphicsContext.WindowContext = @ptrCast(@alignCast(ctx));
    return window_ctx.createShaderModule(spirv);
}
fn destroyShaderModule(ctx: *anyopaque, shader: Interface.Renderer.ShaderModule) void {
    const window_ctx: *GraphicsContext.WindowContext = @ptrCast(@alignCast(ctx));
    window_ctx.destroyShaderModule(shader);
}
fn createGraphicsPipeline(ctx: *anyopaque, info: Interface.Renderer.GraphicsPipelineCreateInfo) !Interface.Renderer.GraphicsPipeline {
    const window_ctx: *GraphicsContext.WindowContext = @ptrCast(@alignCast(ctx));
    return window_ctx.createGraphicsPipeline(info);
}
fn destroyGraphicsPipeline(ctx: *anyopaque, pipeline: Interface.Renderer.GraphicsPipeline) void {
    const window_ctx: *GraphicsContext.WindowContext = @ptrCast(@alignCast(ctx));
    window_ctx.destroyGraphicsPipeline(pipeline);
}
pub fn beginFrame(ctx: *anyopaque, frame: *Interface.Renderer.Frame) !void {
    const window_ctx: *GraphicsContext.WindowContext =
        @ptrCast(@alignCast(ctx));
    frame.state = &window_ctx.frame_state;
    return window_ctx.beginFrame();
}

pub fn bindPipeline(
    ctx: *anyopaque,
    pipeline: Interface.Renderer.GraphicsPipeline,
) !void {
    const window_ctx: *GraphicsContext.WindowContext =
        @ptrCast(@alignCast(ctx));

    return window_ctx.bindPipeline(pipeline);
}

pub fn draw(
    ctx: *anyopaque,
    vertex_count: u32,
    instance_count: u32,
) !void {
    const window_ctx: *GraphicsContext.WindowContext =
        @ptrCast(@alignCast(ctx));

    return window_ctx.draw(vertex_count, instance_count);
}

pub fn endFrame(ctx: *anyopaque) !void {
    const window_ctx: *GraphicsContext.WindowContext =
        @ptrCast(@alignCast(ctx));

    return window_ctx.endFrame();
}
pub fn present(ctx: *anyopaque) !void {
    const window_ctx: *GraphicsContext.WindowContext = @ptrCast(@alignCast(ctx));
    return window_ctx.present();
}
