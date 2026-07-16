const std = @import("std");
const Interface = @import("Interface");
const TrackingAllocator = @import("TrackingAllocator");
const glfw = @import("glfw");
const vulkan = @import("vulkan");
const zgui = @import("zgui");
const zgui_backend = @import("zgui_backend");
const Async = @import("Async");
const Conf = @import("Conf");
const main = @import("main.zig");

pub const Window = Interface.Window(main.interface);

pub fn init(reserve: Async.Reserve) !void {
    const FutureType = Async.Future(@typeInfo(@TypeOf(glfw.init)).@"pub fn".return_type.?);
    var future: FutureType = .{};
    try reserve.call(glfw.init, .{}, FutureType, &future);
    try future.wait();
}
pub fn deinit(reserve: Async.Reserve) !void {
    try reserve.call(glfw.terminate, .{}, void, null);
}

pub fn createWindow(width: c_int, height: c_int, title: [:0]const u8, monitor: ?*Interface.Monitor, share: ?*Window, reserve: Async.Reserve) anyerror!*Window {
    const FutureType = Async.Future(Window);
    var future: FutureType = .{};
    try reserve.call(glfw.createWindow, .{ width, height, title, monitor, if (share) |val| @ptrCast(val) else null }, FutureType, &future);
    return @as(*Window, @ptrCast(future.wait())) catch |err| return err;
}

pub fn destroyWindow(window: *Interface.Window, reserve: Async.Reserve) !void {
    const w: *glfw.Window = @ptrCast(window);
    try reserve.call(glfw.Window.destroy, .{w}, void, null);
}

pub fn windowShouldClose(window: *Interface.Window) bool {
    const w: *glfw.Window = @ptrCast(window);
    return w.shouldClose();
}

pub fn setWindowShouldClose(window: *Interface.Window, should_close: bool, reserve: Async.Reserve) void {
    const w: *glfw.Window = @ptrCast(window);
    try reserve.call(glfw.Window.setShouldClose, .{ w, should_close }, void, null);
}

pub fn setWindowTitle(window: *Interface.Window, title: [:0]const u8, reserve: Async.Reserve) void {
    const w: *glfw.Window = @ptrCast(window);
    try reserve.call(glfw.Window.setTitle, .{ w, title }, void, null);
}

pub fn getWindowSize(window: *Interface.Window) [2]c_int {
    const w: *glfw.Window = @ptrCast(window);
    return w.getSize();
}

pub fn setWindowSize(window: *Interface.Window, width: c_int, height: c_int, reserve: Async.Reserve) void {
    const w: *glfw.Window = @ptrCast(window);
    try reserve.call(glfw.Window.setSize, .{ w, width, height }, void, null);
}

pub fn getWindowFramebufferSize(window: *Interface.Window) [2]c_int {
    const w: *glfw.Window = @ptrCast(window);
    return w.getFramebufferSize();
}

pub fn getWindowPos(window: *Interface.Window) [2]c_int {
    const w: *glfw.Window = @ptrCast(window);
    return w.getPos();
}

pub fn setWindowPos(window: *Interface.Window, xpos: i32, ypos: i32, reserve: Async.Reserve) void {
    const w: *glfw.Window = @ptrCast(window);
    try reserve.call(glfw.Window.setPos, .{ w, xpos, ypos }, void, null);
}

pub fn swapBuffers(window: *Interface.Window, reserve: Async.Reserve) void {
    const w: *glfw.Window = @ptrCast(window);
    try reserve.call(glfw.Window.swapBuffers, .{w}, void, null);
}

pub fn pollEvents(reserve: Async.Reserve) void {
    try reserve.call(glfw.pollEvents, .{}, void, null);
}

pub fn getWindowUserPointer(window: *Interface.Window, T: type) ?*T {
    const w: *glfw.Window = @ptrCast(window);
    return w.getUserPointer(T);
}

pub fn setWindowUserPointer(window: *Interface.Window, pointer: ?*anyopaque, reserve: Async.Reserve) void {
    const w: *glfw.Window = @ptrCast(window);
    try reserve.call(glfw.Window.setUserPointer, .{ w, pointer }, void, null);
}

pub fn getWindowAttributeUntyped(window: *Interface.Window, attrib: Interface.Window.Attribute) c_int {
    const w: *glfw.Window = @ptrCast(window);
    const casted_attrib = @as(glfw.Window.Attribute, @enumFromInt(@intFromEnum(attrib)));
    return w.getAttribute(casted_attrib);
}

pub fn setWindowAttributeUntyped(window: *Interface.Window, attrib: Interface.Window.Attribute, value: c_int, reserve: Async.Reserve) void {
    const w: *glfw.Window = @ptrCast(window);
    const casted_attrib = @as(glfw.Window.Attribute, @enumFromInt(@intFromEnum(attrib)));
    try reserve.call(glfw.setWindowAttributeUntyped, .{ w, casted_attrib, value }, void, null);
}

pub fn iconifyWindow(window: *Interface.Window, reserve: Async.Reserve) void {
    const w: *glfw.Window = @ptrCast(window);
    try reserve.call(glfw.Window.iconify, .{w}, void, null);
}

pub fn restoreWindow(window: *Interface.Window, reserve: Async.Reserve) void {
    const w: *glfw.Window = @ptrCast(window);
    try reserve.call(glfw.Window.restore, .{w}, void, null);
}

pub fn maximizeWindow(window: *Interface.Window, reserve: Async.Reserve) void {
    const w: *glfw.Window = @ptrCast(window);
    try reserve.call(glfw.Window.maximize, .{w}, void, null);
}

pub fn showWindow(window: *Interface.Window, reserve: Async.Reserve) void {
    const w: *glfw.Window = @ptrCast(window);
    try reserve.call(glfw.Window.show, .{w}, void, null);
}

pub fn hideWindow(window: *Interface.Window, reserve: Async.Reserve) void {
    const w: *glfw.Window = @ptrCast(window);
    try reserve.call(glfw.Window.hide, .{w}, void, null);
}

pub fn focusWindow(window: *Interface.Window, reserve: Async.Reserve) void {
    const w: *glfw.Window = @ptrCast(window);
    try reserve.call(glfw.Window.focus, .{w}, void, null);
}

pub fn requestWindowAttention(window: *Interface.Window, reserve: Async.Reserve) void {
    const w: *glfw.Window = @ptrCast(window);
    try reserve.call(glfw.Window.requestAttention, .{w}, void, null);
}

pub fn getKey(window: *Interface.Window, key: Interface.Key) Interface.Action {
    const w: *glfw.Window = @ptrCast(window);
    const casted_key = @as(glfw.Key, @enumFromInt(@intFromEnum(key)));
    return w.getKey(casted_key);
}

pub fn getMouseButton(window: *Interface.Window, button: Interface.MouseButton) Interface.Action {
    const w: *glfw.Window = @ptrCast(window);
    const casted_button = @as(glfw.MouseButton, @enumFromInt(@intFromEnum(button)));
    return w.getMouseButton(casted_button);
}

pub fn getCursorPos(window: *Interface.Window) [2]f64 {
    const w: *glfw.Window = @ptrCast(window);
    return w.getCursorPos();
}

pub fn setCursorPos(window: *Interface.Window, xpos: f64, ypos: f64, reserve: Async.Reserve) void {
    const w: *glfw.Window = @ptrCast(window);
    try reserve.call(glfw.Window.setCursorPos, .{ w, xpos, ypos }, void, null);
}

pub fn setSizeLimits(window: *Interface.Window, min_w: c_int, min_h: c_int, max_w: c_int, max_h: c_int, reserve: Async.Reserve) void {
    const w: *glfw.Window = @ptrCast(window);
    try reserve.call(glfw.Window.setSizeLimits, .{ w, min_w, min_h, max_w, max_h }, void, null);
}

pub fn setAspectRatio(window: *Interface.Window, numer: c_int, denom: c_int, reserve: Async.Reserve) void {
    const w: *glfw.Window = @ptrCast(window);
    try reserve.call(glfw.Window.setAspectRatio, .{ w, numer, denom }, void, null);
}

pub fn getWindowOpacity(window: *Interface.Window) f32 {
    const w: *glfw.Window = @ptrCast(window);
    return w.getOpacity();
}

pub fn setWindowOpacity(window: *Interface.Window, opacity: f32, reserve: Async.Reserve) void {
    const w: *glfw.Window = @ptrCast(window);
    try reserve.call(glfw.Window.setOpacity, .{ w, opacity }, void, null);
}

pub fn getWindowContentScale(window: *Interface.Window) [2]f32 {
    const w: *glfw.Window = @ptrCast(window);
    return w.getContentScale();
}

pub fn getWindowFrameSize(window: *Interface.Window) [4]c_int {
    const w: *glfw.Window = @ptrCast(window);
    return w.getFramebufferSize();
}

pub fn getClipboardString(window: *Interface.Window, reserve: Async.Reserve) ?[:0]const u8 {
    const w: *glfw.Window = @ptrCast(window);
    const FutureType = Async.Future(?[:0]const u8);
    var future: FutureType = .{};
    reserve.call(glfw.Window.getClipboardString, .{w}, FutureType, &future) catch return null;
    return future.wait();
}

pub fn setClipboardString(window: *Interface.Window, string: [:0]const u8, reserve: Async.Reserve) void {
    const w: *glfw.Window = @ptrCast(window);
    try reserve.call(glfw.Window.setClipboardString, .{ w, string }, void, null);
}

pub fn setWindowCursor(window: *Interface.Window, cursor: ?*Interface.Cursor, reserve: Async.Reserve) void {
    const w: *glfw.Window = @ptrCast(window);
    const casted_cursor = @as(?*glfw.Cursor, @ptrCast(cursor));
    try reserve.call(glfw.Window.setCursor, .{ w, casted_cursor }, void, null);
}

pub fn getWindowInputModeUntyped(window: *Interface.Window, mode: Interface.InputMode) c_int {
    const w: *glfw.Window = @ptrCast(window);
    const casted_mode = @as(glfw.InputMode, @enumFromInt(@intFromEnum(mode)));
    return w.getInputMode(casted_mode);
}

pub fn setWindowInputModeUntyped(window: *Interface.Window, mode: Interface.InputMode, value: c_int, reserve: Async.Reserve) void {
    const w: *glfw.Window = @ptrCast(window);
    const casted_mode = @as(glfw.InputMode, @enumFromInt(@intFromEnum(mode)));
    try reserve.call(glfw.setInputModeUntyped, .{ w, casted_mode, value }, void, null);
}

pub fn setFramebufferSizeCallback(window: *Interface.Window, callback: ?Interface.FramebufferSizeFn, reserve: Async.Reserve) ?Interface.FramebufferSizeFn {
    const w: *glfw.Window = @ptrCast(window);
    const casted_cb = @as(?glfw.FramebufferSizeFn, @ptrCast(callback));
    const FutureType = Async.Future(?glfw.FramebufferSizeFn);
    var future: FutureType = .{};
    reserve.call(glfw.Window.setFramebufferSizeCallback, .{ w, casted_cb }, FutureType, &future) catch return null;
    return @ptrCast(future.wait());
}

pub fn setSizeCallback(window: *Interface.Window, callback: ?Interface.WindowSizeFn, reserve: Async.Reserve) ?Interface.WindowSizeFn {
    const w: *glfw.Window = @ptrCast(window);
    const casted_cb = @as(?glfw.WindowSizeFn, @ptrCast(callback));
    const FutureType = Async.Future(?glfw.WindowSizeFn);
    var future: FutureType = .{};
    reserve.call(glfw.Window.setSizeCallback, .{ w, casted_cb }, FutureType, &future) catch return null;
    return @ptrCast(future.wait());
}

pub fn setPosCallback(window: *Interface.Window, callback: ?Interface.WindowPosFn, reserve: Async.Reserve) ?Interface.WindowPosFn {
    const w: *glfw.Window = @ptrCast(window);
    const casted_cb = @as(?glfw.WindowPosFn, @ptrCast(callback));
    const FutureType = Async.Future(?glfw.WindowPosFn);
    var future: FutureType = .{};
    reserve.call(glfw.Window.setPosCallback, .{ w, casted_cb }, FutureType, &future) catch return null;
    return @ptrCast(future.wait());
}

pub fn setFocusCallback(window: *Interface.Window, callback: ?Interface.WindowFocusFn, reserve: Async.Reserve) ?Interface.WindowFocusFn {
    const w: *glfw.Window = @ptrCast(window);
    const casted_cb = @as(?glfw.WindowFocusFn, @ptrCast(callback));
    const FutureType = Async.Future(?glfw.WindowFocusFn);
    var future: FutureType = .{};
    reserve.call(glfw.Window.setFocusCallback, .{ w, casted_cb }, FutureType, &future) catch return null;
    return @ptrCast(future.wait());
}

pub fn setIconifyCallback(window: *Interface.Window, callback: ?Interface.IconifyFn, reserve: Async.Reserve) ?Interface.IconifyFn {
    const w: *glfw.Window = @ptrCast(window);
    const casted_cb = @as(?glfw.IconifyFn, @ptrCast(callback));
    const FutureType = Async.Future(?glfw.IconifyFn);
    var future: FutureType = .{};
    reserve.call(glfw.Window.setIconifyCallback, .{ w, casted_cb }, FutureType, &future) catch return null;
    return @ptrCast(future.wait());
}

pub fn setContentScaleCallback(window: *Interface.Window, callback: ?Interface.WindowContentScalepFn, reserve: Async.Reserve) ?Interface.WindowContentScaleFn {
    const w: *glfw.Window = @ptrCast(window);
    const casted_cb = @as(?glfw.WindowContentScaleFn, @ptrCast(callback));
    const FutureType = Async.Future(?glfw.WindowContentScaleFn);
    var future: FutureType = .{};
    reserve.call(glfw.Window.setContentScaleCallback, .{ w, casted_cb }, FutureType, &future) catch return null;
    return @ptrCast(future.wait());
}

pub fn setCloseCallback(window: *Interface.Window, callback: ?Interface.WindowCloseFn, reserve: Async.Reserve) ?Interface.WindowCloseFn {
    const w: *glfw.Window = @ptrCast(window);
    const casted_cb = @as(?glfw.WindowCloseFn, @ptrCast(callback));
    const FutureType = Async.Future(?glfw.WindowCloseFn);
    var future: FutureType = .{};
    reserve.call(glfw.Window.setCloseCallback, .{ w, casted_cb }, FutureType, &future) catch return null;
    return @ptrCast(future.wait());
}

pub fn setKeyCallback(window: *Interface.Window, callback: ?Interface.KeyFn, reserve: Async.Reserve) ?Interface.KeyFn {
    const w: *glfw.Window = @ptrCast(window);
    const casted_cb = @as(?glfw.KeyFn, @ptrCast(callback));
    const FutureType = Async.Future(?glfw.KeyFn);
    var future: FutureType = .{};
    reserve.call(glfw.Window.setKeyCallback, .{ w, casted_cb }, FutureType, &future) catch return null;
    return @ptrCast(future.wait());
}

pub fn setCharCallback(window: *Interface.Window, callback: ?Interface.CharFn, reserve: Async.Reserve) ?Interface.CharFn {
    const w: *glfw.Window = @ptrCast(window);
    const casted_cb = @as(?glfw.CharFn, @ptrCast(callback));
    const FutureType = Async.Future(?glfw.CharFn);
    var future: FutureType = .{};
    reserve.call(glfw.Window.setCharCallback, .{ w, casted_cb }, FutureType, &future) catch return null;
    return @ptrCast(future.wait());
}

pub fn setDropCallback(window: *Interface.Window, callback: ?Interface.DropFn, reserve: Async.Reserve) ?Interface.DropFn {
    const w: *glfw.Window = @ptrCast(window);
    const casted_cb = @as(?glfw.DropFn, @ptrCast(callback));
    const FutureType = Async.Future(?glfw.DropFn);
    var future: FutureType = .{};
    reserve.call(glfw.Window.setDropCallback, .{ w, casted_cb }, FutureType, &future) catch return null;
    return @ptrCast(future.wait());
}

pub fn setMouseButtonCallback(window: *Interface.Window, callback: ?Interface.MouseButtonFn, reserve: Async.Reserve) ?Interface.MouseButtonFn {
    const w: *glfw.Window = @ptrCast(window);
    const casted_cb = @as(?glfw.MouseButtonFn, @ptrCast(callback));
    const FutureType = Async.Future(?glfw.MouseButtonFn);
    var future: FutureType = .{};
    reserve.call(glfw.Window.setMouseButtonCallback, .{ w, casted_cb }, FutureType, &future) catch return null;
    return @ptrCast(future.wait());
}

pub fn setScrollCallback(window: *Interface.Window, callback: ?Interface.ScrollFn, reserve: Async.Reserve) ?Interface.ScrollFn {
    const w: *glfw.Window = @ptrCast(window);
    const casted_cb = @as(?glfw.ScrollFn, @ptrCast(callback));
    const FutureType = Async.Future(?glfw.ScrollFn);
    var future: FutureType = .{};
    reserve.call(glfw.Window.setScrollCallback, .{ w, casted_cb }, FutureType, &future) catch return null;
    return @ptrCast(future.wait());
}

pub fn setCursorPosCallback(window: *Interface.Window, callback: ?Interface.CursorPosFn, reserve: Async.Reserve) ?Interface.CursorPosFn {
    const w: *glfw.Window = @ptrCast(window);
    const casted_cb = @as(?glfw.CursorPosFn, @ptrCast(callback));
    const FutureType = Async.Future(?glfw.CursorPosFn);
    var future: FutureType = .{};
    reserve.call(glfw.Window.setCursorPosCallback, .{ w, casted_cb }, FutureType, &future) catch return null;
    return @ptrCast(future.wait());
}

pub fn setCursorEnterCallback(window: *Interface.Window, callback: ?Interface.CursorEnterFn, reserve: Async.Reserve) ?Interface.CursorEnterFn {
    const w: *glfw.Window = @ptrCast(window);
    const casted_cb = @as(?glfw.CursorEnterFn, @ptrCast(callback));
    const FutureType = Async.Future(?glfw.CursorEnterFn);
    var future: FutureType = .{};
    reserve.call(glfw.Window.setCursorEnterCallback, .{ w, casted_cb }, FutureType, &future) catch return null;
    return @ptrCast(future.wait());
}
