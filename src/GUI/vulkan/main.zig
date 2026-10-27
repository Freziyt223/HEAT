const std = @import("std");
const vulkan = @import("vulkan");
const glfw = @import("glfw");
const zgui = @import("zgui");
const TrackingAllocator = @import("TrackingAllocator");
const Interface = @import("Interface");
const Async = @import("Async");
const WindowContext = @import("window.zig");
const GraphicsContext = @import("global.zig");
var global_ctx: GraphicsContext = undefined;
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
    .destroyShaderModule = &destroyShaderModule,
    .createGraphicsPipeline = @ptrCast(&createGraphicsPipeline),
    .destroyGraphicsPipeline = &destroyGraphicsPipeline,
    .createVertexBuffer = @ptrCast(&createVertexBuffer),
    .destroyVertexBuffer = &destroyVertexBuffer,
    .bindVertexBuffer = @ptrCast(&bindVertexBuffer),
    .createIndexBuffer = @ptrCast(&createIndexBuffer),
    .destroyIndexBuffer = &destroyIndexBuffer,
    .bindIndexBuffer = @ptrCast(&bindIndexBuffer),
    .createDescriptorSetLayout = @ptrCast(&createDescriptorSetLayout),
    .destroyDescriptorSetLayout = &destroyDescriptorSetLayout,
    .createDescriptorPool = @ptrCast(&createDescriptorPool),
    .destroyDescriptorPool = &destroyDescriptorPool,
    .allocateDescriptorSets = @ptrCast(&allocateDescriptorSets),
    .freeDescriptorSets = @ptrCast(&freeDescriptorSets),
    .bindDescriptorSets = @ptrCast(&bindDescriptorSets),
};

pub fn getInterface() Interface {
    return interface;
}

pub fn init(allocator: std.mem.Allocator) anyerror!void {
    try try Async.callMainSync(internal_init, .{allocator});
}
fn internal_init(allocator: std.mem.Allocator) !void {
    Allocator = TrackingAllocator.init(allocator, "VulkanAllocator");
    try glfw.init();
    if (!glfw.isVulkanSupported()) {
        std.debug.print("GLFW couldn't find libvulkan\n", .{});
        return error.NoVulkan;
    }
    glfw.windowHint(.client_api, .no_api);
    glfw.windowHint(.visible, true);

    global_ctx = try GraphicsContext.init(Allocator.allocator());
}
pub fn deinit() void {
    global_ctx.deinit();
    glfw.terminate();
}

pub fn initWindow(renderer: Interface, window: *Interface.Window, queue_index: u32) !Interface.Renderer {
    glfw.windowHint(.client_api, .no_api);
    glfw.windowHint(.visible, true);
    const window_ctx = try try Async.callMainSync(
        WindowContext.init,
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
    const window_ctx: *WindowContext = @ptrCast(@alignCast(self.ctx));
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

pub fn createShaderModule(ctx: *anyopaque, spirv: []const u8) !Interface.Renderer.ShaderModule {
    const window_ctx: *WindowContext = @ptrCast(@alignCast(ctx));
    return window_ctx.createShaderModule(spirv);
}
pub fn destroyShaderModule(ctx: *anyopaque, shader: Interface.Renderer.ShaderModule) void {
    const window_ctx: *WindowContext = @ptrCast(@alignCast(ctx));
    window_ctx.destroyShaderModule(shader);
}
pub fn createGraphicsPipeline(ctx: *anyopaque, info: Interface.Renderer.GraphicsPipelineCreateInfo) !Interface.Renderer.GraphicsPipeline {
    const window_ctx: *WindowContext = @ptrCast(@alignCast(ctx));
    return window_ctx.createGraphicsPipeline(info);
}
pub fn destroyGraphicsPipeline(ctx: *anyopaque, pipeline: Interface.Renderer.GraphicsPipeline) void {
    const window_ctx: *WindowContext = @ptrCast(@alignCast(ctx));
    window_ctx.destroyGraphicsPipeline(pipeline);
}

pub fn createVertexBuffer(ctx: *anyopaque, verticies: []const u8) !Interface.Renderer.VertexBuffer {
    const window_ctx: *WindowContext = @ptrCast(@alignCast(ctx));
    return window_ctx.createVertexBuffer(&global_ctx, verticies);
}
pub fn destroyVertexBuffer(ctx: *anyopaque, buffer: Interface.Renderer.VertexBuffer) void {
    const window_ctx: *WindowContext = @ptrCast(@alignCast(ctx));
    window_ctx.destroyVertexBuffer(buffer);
}
pub fn bindVertexBuffer(ctx: *anyopaque, buffer: Interface.Renderer.VertexBuffer) !void {
    const window_ctx: *WindowContext = @ptrCast(@alignCast(ctx));
    return window_ctx.bindVertexBuffer(buffer);
}

pub fn createIndexBuffer(ctx: *anyopaque, indicies: []const u8) !Interface.Renderer.IndexBuffer {
    const window_ctx: *WindowContext = @ptrCast(@alignCast(ctx));
    return window_ctx.createIndexBuffer(&global_ctx, indicies);
}
pub fn destroyIndexBuffer(ctx: *anyopaque, buffer: Interface.Renderer.IndexBuffer) void {
    const window_ctx: *WindowContext = @ptrCast(@alignCast(ctx));
    window_ctx.destroyIndexBuffer(buffer);
}
pub fn bindIndexBuffer(ctx: *anyopaque, buffer: Interface.Renderer.IndexBuffer) !void {
    const window_ctx: *WindowContext = @ptrCast(@alignCast(ctx));
    return window_ctx.bindIndexBuffer(buffer);
}
pub fn createDescriptorSetLayout(ctx: *anyopaque, info: Interface.Renderer.DescriptorSetLayoutCreateInfo) !Interface.Renderer.DescriptorSetLayout {
    const window_ctx: *WindowContext = @ptrCast(@alignCast(ctx));
    return window_ctx.createDescriptorSetLayout(info);
}
pub fn destroyDescriptorSetLayout(ctx: *anyopaque, layout: Interface.Renderer.DescriptorSetLayout) void {
    const window_ctx: *WindowContext = @ptrCast(@alignCast(ctx));
    window_ctx.destroyDescriptorSetLayout(layout);
}
pub fn createDescriptorPool(ctx: *anyopaque, info: Interface.Renderer.DescriptorPoolCreateInfo) !Interface.Renderer.DescriptorPool {
    const window_ctx: *WindowContext = @ptrCast(@alignCast(ctx));
    return window_ctx.createDescriptorPool(info);
}
pub fn destroyDescriptorPool(ctx: *anyopaque, pool: Interface.Renderer.DescriptorPool) void {
    const window_ctx: *WindowContext = @ptrCast(@alignCast(ctx));
    window_ctx.destroyDescriptorPool(pool);
}
pub fn allocateDescriptorSets(ctx: *anyopaque, pool: Interface.Renderer.DescriptorPool, layouts: []const Interface.Renderer.DescriptorSetLayout, allocator: std.mem.Allocator) ![]Interface.Renderer.DescriptorSet {
    const window_ctx: *WindowContext = @ptrCast(@alignCast(ctx));
    return window_ctx.allocateDescriptorSets(pool, layouts, allocator);
}
pub fn freeDescriptorSets(ctx: *anyopaque, pool: Interface.Renderer.DescriptorPool, sets: []const Interface.Renderer.DescriptorSet) !void {
    const window_ctx: *WindowContext = @ptrCast(@alignCast(ctx));
    return window_ctx.freeDescriptorSets(pool, sets);
}
pub fn bindDescriptorSets(ctx: *anyopaque, pipeline: Interface.Renderer.GraphicsPipeline, first_set: u32, sets: []const Interface.Renderer.DescriptorSet) !void {
    const window_ctx: *WindowContext = @ptrCast(@alignCast(ctx));
    return window_ctx.bindDescriptorSets(pipeline, first_set, sets);
}
pub fn beginFrame(ctx: *anyopaque, frame: *Interface.Renderer.Frame) !void {
    const window_ctx: *WindowContext =
        @ptrCast(@alignCast(ctx));
    frame.state = &window_ctx.frame_state;
    return window_ctx.beginFrame(&global_ctx);
}

pub fn bindPipeline(
    ctx: *anyopaque,
    pipeline: Interface.Renderer.GraphicsPipeline,
) !void {
    const window_ctx: *WindowContext =
        @ptrCast(@alignCast(ctx));

    return window_ctx.bindPipeline(pipeline);
}

pub fn draw(
    ctx: *anyopaque,
    indicies_count: u32,
    instance_count: u32,
) !void {
    const window_ctx: *WindowContext =
        @ptrCast(@alignCast(ctx));

    return window_ctx.draw(indicies_count, instance_count);
}

pub fn endFrame(ctx: *anyopaque) !void {
    const window_ctx: *WindowContext =
        @ptrCast(@alignCast(ctx));

    return window_ctx.endFrame();
}
pub fn present(ctx: *anyopaque) !void {
    const window_ctx: *WindowContext = @ptrCast(@alignCast(ctx));
    return window_ctx.present();
}
