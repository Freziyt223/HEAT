const std = @import("std");
const Interface = @import("Interface").Interface;
const TrackingAllocator = @import("TrackingAllocator");
const glfw = @import("glfw");
const vulkan = @import("vulkan");
const zgui_backend = @import("zgui_backend");
const Async = @import("Async");
const Conf = @import("Conf");
const glfw_impl = @import("glfw.zig");
const graphics_context = @import("graphics_context.zig");

pub var Allocator: TrackingAllocator = undefined;
pub const Config = struct {};
pub var config = Config{};
pub const Window = Interface.Window(interface);

pub const interface = Interface{
    .init = @ptrCast(&init),
    .deinit = &deinit,
    .createWindow = &createWindow,
    .destroyWindow = &glfw.destroyWindow,
    .windowShouldClose = &glfw.windowShouldClose,
    .setWindowShouldClose = &glfw.setWindowShouldClose,
    .setWindowTitle = &glfw.setWindowTitle,
    .getWindowSize = &glfw.getWindowSize,
    .setWindowSize = &glfw.setWindowSize,
    .getWindowFramebufferSize = &glfw.getWindowFramebufferSize,
    .getWindowPos = &glfw.getWindowPos,
    .setWindowPos = &glfw.setWindowPos,
    .swapBuffers = &glfw.swapBuffers,
    .pollEvents = &glfw.pollEvents,
    .getWindowUserPointer = &glfw.getWindowUserPointer,
    .setWindowUserPointer = &glfw.setWindowUserPointer,
    .getWindowAttributeUntyped = &glfw.getWindowAttributeUntyped,
    .setWindowAttributeUntyped = &glfw.setWindowAttributeUntyped,

    .iconifyWindow = &glfw.iconifyWindow,
    .restoreWindow = &glfw.restoreWindow,
    .maximizeWindow = &glfw.maximizeWindow,
    .showWindow = &glfw.showWindow,
    .hideWindow = &glfw.hideWindow,
    .focusWindow = &glfw.focusWindow,
    .requestWindowAttention = &glfw.requestWindowAttention,

    .getKey = &glfw.getKey,
    .getMouseButton = &glfw.getMouseButton,
    .getCursorPos = &glfw.getCursorPos,
    .setCursorPos = &glfw.setCursorPos,

    .setSizeLimits = &glfw.setSizeLimits,
    .setAspectRatio = &glfw.setAspectRatio,
    .getWindowOpacity = &glfw.getWindowOpacity,
    .setWindowOpacity = &glfw.setWindowOpacity,
    .getWindowContentScale = &glfw.getWindowContentScale,
    .getWindowFrameSize = &glfw.getWindowFrameSize,

    .getClipboardString = &glfw.getClipboardString,
    .setClipboardString = &glfw.setClipboardString,
    .setWindowCursor = &glfw.setWindowCursor,

    .getWindowInputModeUntyped = &glfw.getWindowInputModeUntyped,
    .setWindowInputModeUntyped = &glfw.setWindowInputModeUntyped,

    .setFramebufferSizeCallback = &glfw.setFramebufferSizeCallback,
    .setSizeCallback = &glfw.setSizeCallback,
    .setPosCallback = &glfw.setPosCallback,
    .setFocusCallback = &glfw.setFocusCallback,
    .setIconifyCallback = &glfw.setIconifyCallback,
    .setContentScaleCallback = &glfw.setContentScaleCallback,
    .setCloseCallback = &glfw.setCloseCallback,
    .setKeyCallback = &glfw.setKeyCallback,
    .setCharCallback = &glfw.setCharCallback,
    .setDropCallback = &glfw.setDropCallback,
    .setMouseButtonCallback = &glfw.setMouseButtonCallback,
    .setScrollCallback = &glfw.setScrollCallback,
    .setCursorPosCallback = &glfw.setCursorPosCallback,
    .setCursorEnterCallback = &glfw.setCursorEnterCallback,

    .config = &config,
    .config_t = config_t,
};

pub export fn getApi() callconv(.c) *const Interface {
    return &interface;
}

pub fn config_t() type {
    return Config;
}
const InitError = error{
    Nolibvulkan,
};
pub fn init(allocator: std.mem.Allocator, reserve: Async.Reserve) !void {
    Allocator = TrackingAllocator.init(allocator, "VulkanAllocator");
    const FutureType = Async.Future(@typeInfo(@TypeOf(glfw_impl.init)).@"fn".return_type.?);
    var future: FutureType = .{};
    try reserve.call(glfw_impl.init, .{}, FutureType, &future);
    try future.wait();

    if (!glfw.isVulkanSupported()) return InitError.Nolibvulkan;

    glfw.windowHint(.client_api, .no_api);
}

pub fn deinit(reserve: Async.Reserve) !void {
    // Vulkan cleanup here
    try reserve.call(glfw_impl.deinit, .{}, void, null);
}

pub fn createWindow(width: u32, height: u32, title: [:0]const u8, monitor: ?*glfw.Monitor, share: ?*Window, reserve: Async.Reserve) anyerror!*Window {
    const FutureType = Async.Future(Window);
    var future: FutureType = .{};
    var extent = vulkan.Extent2D{ .width = width, .height = height };
    try reserve.call(glfw_impl.createWindow, .{ @intCast(extent.width), @intCast(extent.height), title, monitor, if (share) |val| @ptrCast(val) else null }, FutureType, &future);
    const window = @as(*Window, @ptrCast(future.wait())) catch |err| return err;

    extent.width, extent.height = blk: {
        var w: c_int = undefined;
        var h: c_int = undefined;
        glfw.getFramebufferSize(@ptrCast(window), &w, &h);
        break :blk .{ @intCast(w), @intCast(h) };
    };
    // Vulkan initialization here so it's only initialized when window is created(and not repeated when already initialized)
}
