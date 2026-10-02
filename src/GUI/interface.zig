const std = @import("std");
const builtin = @import("builtin");
const Async = @import("Async");
const zglfw = @import("zglfw");

const Self = @This();

init: *const fn (std.mem.Allocator) anyerror!void,
deinit: *const fn () void,
initWindow: *const fn (Self, *Window, u32) Renderer,
deinitWindow: *const fn (Renderer) void,
switchPhysicalDevice: *const fn (DeviceSelection, *DeviceInfo) anyerror!void,
enumeratePhysicalDevices: *const fn (std.mem.Allocator) anyerror![]DeviceInfo,
getPhysicalDevice: *const fn () DeviceInfo,
beginFrame: *const fn (*anyopaque, *Renderer.Frame) anyerror!void,
bindPipeline: *const fn (*anyopaque, Renderer.GraphicsPipeline) anyerror!void,
draw: *const fn (*anyopaque, u32, u32) anyerror!void,
endFrame: *const fn (*anyopaque) anyerror!void,
present: *const fn (*anyopaque) anyerror!void,
createShaderModule: *const fn (*anyopaque, []const u8) anyerror!Renderer.ShaderModule,
destroyShaderModule: *const fn (*anyopaque, Renderer.ShaderModule) void,
createGraphicsPipeline: *const fn (*anyopaque, Renderer.GraphicsPipelineCreateInfo) anyerror!Renderer.GraphicsPipeline,
destroyGraphicsPipeline: *const fn (*anyopaque, Renderer.GraphicsPipeline) void,

pub const Renderer = struct {
    window: *anyopaque,
    renderer: Self,
    ctx: *anyopaque,
    pub fn Handle(comptime Tag: anytype) type {
        return struct {
            index: u32,
            generation: u32,

            pub const tag = Tag;

            pub fn invalid() @This() {
                return .{
                    .index = std.math.maxInt(u32),
                    .generation = 0,
                };
            }

            pub fn isValid(self: @This()) bool {
                return self.index != std.math.maxInt(u32);
            }
        };
    }
    pub const FrameState = enum(u8) {
        idle,
        recording,
        closing,
        destroyed,
    };
    pub const Frame = struct {
        renderer: Renderer,
        state: *std.atomic.Value(FrameState),

        pub fn bindPipeline(self: *Frame, graphicsPipeline: GraphicsPipeline) !void {
            return self.renderer.renderer.bindPipeline(self.renderer.ctx, graphicsPipeline);
        }
        pub fn draw(self: *Frame, vertex_count: u32, instance_count: u32) !void {
            return self.renderer.renderer.draw(self.renderer.ctx, vertex_count, instance_count);
        }
        pub fn present(self: *Frame) !void {
            return self.renderer.renderer.present(self.renderer.ctx);
        }
        pub fn end(self: *Frame) !void {
            return self.renderer.renderer.endFrame(self.renderer.ctx);
        }
    };

    pub const ShaderModule = Handle(.shader_module);
    pub const GraphicsPipeline = Handle(.graphics_pipeline);
    pub const Buffer = Handle(.buffer);
    pub const Image = Handle(.image);
    pub const PipelineLayout = Handle(.pipeline_layout);

    pub fn deinit(self: Renderer) void {
        self.renderer.deinitWindow(self);
    }
    pub fn switchPhysicalDevice(self: Renderer, selection: DeviceSelection) void {
        self.renderer.switchPhysicalDevice(selection, &self.device);
    }
    pub fn enumeratePhysicalDevices(self: Renderer, allocator: std.mem.Allocator) ![]DeviceInfo {
        return self.renderer.enumeratePhysicalDevices(allocator);
    }
    pub fn getPhysicalDevice(self: Renderer) DeviceInfo {
        return self.renderer.getPhysicalDevice();
    }

    pub fn createShaderModule(self: Renderer, spirv: []const u8) !ShaderModule {
        return self.renderer.createShaderModule(self.ctx, spirv);
    }
    pub fn beginFrame(self: Renderer) !Frame {
        var frame = Renderer.Frame{
            .renderer = self,
            .state = undefined,
        };
        try self.renderer.beginFrame(self.ctx, &frame);
        return frame;
    }

    pub fn destroyShaderModule(
        self: Renderer,
        shader: ShaderModule,
    ) void {
        self.renderer.destroyShaderModule(self.ctx, shader);
    }

    pub const GraphicsPipelineCreateInfo = struct {
        vertex_shader: Renderer.ShaderModule,
        fragment_shader: Renderer.ShaderModule,

        vertex_input: VertexInputState = .{},

        topology: PrimitiveTopology = .triangle_list,

        cull_mode: CullMode = .back,
        front_face: FrontFace = .counter_clockwise,

        depth_test: bool = false,
        depth_write: bool = false,

        blend: BlendState = .{},
    };

    pub const VertexInputState = struct {
        bindings: []const VertexBinding = &.{},
        attributes: []const VertexAttribute = &.{},
    };

    pub const VertexBinding = struct {
        binding: u32,
        stride: u32,
        input_rate: VertexInputRate = .vertex,
    };

    pub const VertexAttribute = struct {
        location: u32,
        binding: u32,
        format: VertexFormat,
        offset: u32,
    };

    pub const VertexInputRate = enum {
        vertex,
        instance,
    };

    pub const VertexFormat = enum {
        float32,
        float32x2,
        float32x3,
        float32x4,

        uint32,
        uint32x2,
        uint32x3,
        uint32x4,

        sint32,
        sint32x2,
        sint32x3,
        sint32x4,
    };

    pub const PrimitiveTopology = enum {
        point_list,
        line_list,
        line_strip,
        triangle_list,
        triangle_strip,
        triangle_fan,
    };

    pub const CullMode = enum {
        none,
        front,
        back,
        front_and_back,
    };

    pub const FrontFace = enum {
        counter_clockwise,
        clockwise,
    };

    pub const BlendState = struct {
        enabled: bool = false,
    };

    pub fn createGraphicsPipeline(self: Renderer, info: GraphicsPipelineCreateInfo) !GraphicsPipeline {
        return self.renderer.createGraphicsPipeline(self.ctx, info);
    }
    pub fn destroyGraphicsPipeline(self: Renderer, pipeline: GraphicsPipeline) void {
        self.renderer.destroyGraphicsPipeline(self.ctx, pipeline);
    }
};

pub const GpuPreference = enum {
    discrete,
    integrated,
    index,
    name,
};

pub const DeviceSelection = union(GpuPreference) {
    discrete: void,
    integrated: void,
    index: usize,
    name: []const u8,
};

pub const PhysicalDeviceType = enum(c_int) {
    other = 0,
    integrated_gpu = 1,
    discrete_gpu = 2,
    virtual_gpu = 3,
    cpu = 4,
    _,
};

pub const DeviceInfo = struct {
    index: u32,
    name: [256]u8,
    type: PhysicalDeviceType,
};

pub const Window = opaque {
    inline fn toGlfwWindow(self: *Window) *zglfw.Window {
        return @as(*zglfw.Window, @ptrCast(self));
    }

    pub inline fn setupRenderer(self: *Window, implementation: Self, queue_index: u32) !Renderer {
        return implementation.initWindow(implementation, self, queue_index);
    }

    pub fn shouldClose(self: *Window) bool {
        return Async.callMainSync(zglfw.windowShouldClose, .{self.toGlfwWindow()}) catch |err| {
            std.debug.print("Got an error: {} when checking shouldClose!\n", .{err});
            return false;
        };
    }

    pub fn setShouldClose(self: *Window, value: bool) void {
        Async.callMainSync(zglfw.setWindowShouldClose, .{ self.toGlfwWindow(), value }) catch |err| {
            std.debug.print("Got an error: {} when setting shouldClose!\n", .{err});
        };
    }

    pub fn swapBuffers(self: *Window) void {
        Async.callMainSync(zglfw.swapBuffers, .{self.toGlfwWindow()}) catch |err| {
            std.debug.print("Got an error: {} when swapping buffers!\n", .{err});
        };
    }

    pub fn getUserPointer(self: *Window, comptime T: type) ?*T {
        return Async.callMainSync(zglfw.getWindowUserPointer, .{ self.toGlfwWindow(), T }) catch |err| {
            std.debug.print("Got an error: {} when getting user pointer!\n", .{err});
            return null;
        };
    }

    pub fn setUserPointer(self: *Window, pointer: ?*anyopaque) void {
        Async.callMainSync(zglfw.setWindowUserPointer, .{ self.toGlfwWindow(), pointer }) catch |err| {
            std.debug.print("Got an error: {} when setting user pointer!\n", .{err});
        };
    }

    pub fn create(width: i32, height: i32, title: [:0]const u8, monitor: ?*zglfw.Monitor, share: ?*zglfw.Window) !?*Window {
        const handle = try try Async.callMainSync(zglfw.createWindow, .{ width, height, title, monitor, share });
        return @as(*Window, @ptrCast(handle));
    }

    pub fn destroy(self: *Window) void {
        Async.callMain(zglfw.destroyWindow, .{self.toGlfwWindow()}, void, null) catch |err| {
            std.debug.print("Got an error: {} when destroying the window!\n", .{err});
        };
    }

    pub fn getSize(self: *Window) [2]c_int {
        return Async.callMainSync(zglfw.Window.getSize, .{self.toGlfwWindow()}) catch |err| {
            std.debug.print("Got an error: {} when getting size!\n", .{err});
            return .{ 0, 0 };
        };
    }

    pub fn getFramebufferSize(self: *Window) [2]c_int {
        return Async.callMainSync(zglfw.Window.getFramebufferSize, .{self.toGlfwWindow()}) catch |err| {
            std.debug.print("Got an error: {} when getting framebuffer size!\n", .{err});
            return .{ 0, 0 };
        };
    }

    pub fn getPos(self: *Window) [2]c_int {
        return Async.callMainSync(zglfw.Window.getPos, .{self.toGlfwWindow()}) catch |err| {
            std.debug.print("Got an error: {} when getting position!\n", .{err});
            return .{ 0, 0 };
        };
    }

    pub fn getCursorPos(self: *Window) [2]f64 {
        return Async.callMainSync(zglfw.Window.getCursorPos, .{self.toGlfwWindow()}) catch |err| {
            std.debug.print("Got an error: {} when getting cursor position!\n", .{err});
            return .{ 0.0, 0.0 };
        };
    }

    pub fn getContentScale(self: *Window) [2]f32 {
        return Async.callMainSync(zglfw.Window.getContentScale, .{self.toGlfwWindow()}) catch |err| {
            std.debug.print("Got an error: {} when getting content scale!\n", .{err});
            return .{ 1.0, 1.0 };
        };
    }

    pub fn getFrameSize(self: *Window) [4]c_int {
        return Async.callMainSync(zglfw.Window.getFrameSize, .{self.toGlfwWindow()}) catch |err| {
            std.debug.print("Got an error: {} when getting frame size!\n", .{err});
            return .{ 0, 0, 0, 0 };
        };
    }

    pub fn getOpacity(self: *Window) f32 {
        return Async.callMainSync(zglfw.getWindowOpacity, .{self.toGlfwWindow()}) catch |err| {
            std.debug.print("Got an error: {} when getting opacity!\n", .{err});
            return 1.0;
        };
    }

    pub fn getAttribute(self: *Window, attrib: zglfw.Window.Attribute) c_int {
        return Async.callMainSync(zglfw.getWindowAttribute, .{ self.toGlfwWindow(), attrib }) catch |err| {
            std.debug.print("Got an error: {} when getting attribute!\n", .{err});
            return 0;
        };
    }

    pub fn getKey(self: *Window, key: zglfw.Key) zglfw.Action {
        return Async.callMainSync(zglfw.getKey, .{ self.toGlfwWindow(), key }) catch |err| {
            std.debug.print("Got an error: {} when getting key!\n", .{err});
            return .release;
        };
    }

    pub fn getMouseButton(self: *Window, button: zglfw.MouseButton) zglfw.Action {
        return Async.callMainSync(zglfw.getMouseButton, .{ self.toGlfwWindow(), button }) catch |err| {
            std.debug.print("Got an error: {} when getting mouse button!\n", .{err});
            return .release;
        };
    }

    pub fn getClipboardString(self: *Window) [:0]const u8 {
        return Async.callMainSync(zglfw.getClipboardString, .{self.toGlfwWindow()}) catch |err| {
            std.debug.print("Got an error: {} when getting clipboard string!\n", .{err});
            return "";
        };
    }

    pub fn setSize(self: *Window, width: i32, height: i32) void {
        Async.callMainSync(zglfw.setWindowSize, .{ self.toGlfwWindow(), width, height }) catch |err| {
            std.debug.print("Got an error: {} when setting size!\n", .{err});
        };
    }

    pub fn setPos(self: *Window, x: i32, y: i32) void {
        Async.callMainSync(zglfw.setWindowPos, .{ self.toGlfwWindow(), x, y }) catch |err| {
            std.debug.print("Got an error: {} when setting position!\n", .{err});
        };
    }

    pub fn setTitle(self: *Window, title: [:0]const u8) void {
        Async.callMainSync(zglfw.setWindowTitle, .{ self.toGlfwWindow(), title }) catch |err| {
            std.debug.print("Got an error: {} when setting title!\n", .{err});
        };
    }

    pub fn setOpacity(self: *Window, opacity: f32) void {
        Async.callMainSync(zglfw.setWindowOpacity, .{ self.toGlfwWindow(), opacity }) catch |err| {
            std.debug.print("Got an error: {} when setting opacity!\n", .{err});
        };
    }

    pub fn show(self: *Window) void {
        Async.callMainSync(zglfw.showWindow, .{self.toGlfwWindow()}) catch |err| {
            std.debug.print("Got an error: {} when showing window!\n", .{err});
        };
    }

    pub fn hide(self: *Window) void {
        Async.callMainSync(zglfw.hideWindow, .{self.toGlfwWindow()}) catch |err| {
            std.debug.print("Got an error: {} when hiding window!\n", .{err});
        };
    }

    pub fn focus(self: *Window) void {
        Async.callMainSync(zglfw.focusWindow, .{self.toGlfwWindow()}) catch |err| {
            std.debug.print("Got an error: {} when focusing window!\n", .{err});
        };
    }

    pub fn iconify(self: *Window) void {
        Async.callMainSync(zglfw.iconifyWindow, .{self.toGlfwWindow()}) catch |err| {
            std.debug.print("Got an error: {} when iconifying window!\n", .{err});
        };
    }

    pub fn restore(self: *Window) void {
        Async.callMainSync(zglfw.restoreWindow, .{self.toGlfwWindow()}) catch |err| {
            std.debug.print("Got an error: {} when restoring window!\n", .{err});
        };
    }

    pub fn maximize(self: *Window) void {
        Async.callMainSync(zglfw.maximizeWindow, .{self.toGlfwWindow()}) catch |err| {
            std.debug.print("Got an error: {} when maximizing window!\n", .{err});
        };
    }

    pub fn requestAttention(self: *Window) void {
        Async.callMainSync(zglfw.requestWindowAttention, .{self.toGlfwWindow()}) catch |err| {
            std.debug.print("Got an error: {} when requesting attention!\n", .{err});
        };
    }

    pub fn setClipboardString(self: *Window, string: [:0]const u8) void {
        Async.callMainSync(zglfw.setClipboardString, .{ self.toGlfwWindow(), string }) catch |err| {
            std.debug.print("Got an error: {} when setting clipboard string!\n", .{err});
        };
    }

    pub fn setFramebufferSizeCallback(self: *Window, cbfun: ?zglfw.FramebufferSizeFn) ?zglfw.FramebufferSizeFn {
        return Async.callMainSync(zglfw.setFramebufferSizeCallback, .{ self.toGlfwWindow(), cbfun }) catch |err| {
            std.debug.print("Got an error: {} when setting framebuffer size callback!\n", .{err});
            return null;
        };
    }

    pub fn setKeyCallback(self: *Window, cbfun: ?zglfw.KeyFn) ?zglfw.KeyFn {
        return Async.callMainSync(zglfw.setKeyCallback, .{ self.toGlfwWindow(), cbfun }) catch |err| {
            std.debug.print("Got an error: {} when setting key callback!\n", .{err});
            return null;
        };
    }

    pub fn setCursorPosCallback(self: *Window, cbfun: ?zglfw.CursorPosFn) ?zglfw.CursorPosFn {
        return Async.callMainSync(zglfw.setCursorPosCallback, .{ self.toGlfwWindow(), cbfun }) catch |err| {
            std.debug.print("Got an error: {} when setting cursor pos callback!\n", .{err});
            return null;
        };
    }

    pub fn setMouseButtonCallback(self: *Window, cbfun: ?zglfw.MouseButtonFn) ?zglfw.MouseButtonFn {
        return Async.callMainSync(zglfw.setMouseButtonCallback, .{ self.toGlfwWindow(), cbfun }) catch |err| {
            std.debug.print("Got an error: {} when setting mouse button callback!\n", .{err});
            return null;
        };
    }
};

fn getNativeWindowHandle(window: *Window) ?*anyopaque {
    const handle = window.toGlfwWindow();
    const platform = Async.callMainSync(zglfw.getPlatform, .{}) catch |err| {
        std.debug.print("Got an error: {} when getting platform!\n", .{err});
        return null;
    };

    switch (builtin.os.tag) {
        .windows => {
            const win32 = Async.callMainSync(zglfw.getWin32Window, .{handle}) catch |err| {
                std.debug.print("Got an error: {} when getting Win32 window!\n", .{err});
                return null;
            };
            return win32.?;
        },
        .linux => {
            if (platform == .wayland) {
                const wayland = Async.callMainSync(zglfw.getWaylandWindow, .{handle}) catch |err| {
                    std.debug.print("Got an error: {} when getting Wayland window!\n", .{err});
                    return null;
                };
                return wayland.?;
            } else {
                const x11_window = Async.callMainSync(zglfw.getX11Window, .{handle}) catch |err| {
                    std.debug.print("Got an error: {} when getting X11 window!\n", .{err});
                    return 0;
                };
                return @ptrFromInt(x11_window);
            }
        },
        .macos => {
            const cocoa = Async.callMainSync(zglfw.getCocoaWindow, .{handle}) catch |err| {
                std.debug.print("Got an error: {} when getting Cocoa window!\n", .{err});
                return null;
            };
            return cocoa.?;
        },
        else => @panic("Unsupported OS platform"),
    }
}

fn getNativeDisplayType() ?*anyopaque {
    if (builtin.os.tag == .linux) {
        const platform = Async.callMainSync(zglfw.getPlatform, .{}) catch |err| {
            std.debug.print("Got an error: {} when getting platform!\n", .{err});
            return null;
        };
        if (platform == .wayland) {
            return Async.callMainSync(zglfw.getWaylandDisplay, .{}) catch |err| {
                std.debug.print("Got an error: {} when getting Wayland display!\n", .{err});
                return null;
            };
        } else {
            return Async.callMainSync(zglfw.getX11Display, .{}) catch |err| {
                std.debug.print("Got an error: {} when getting X11 display!\n", .{err});
                return null;
            };
        }
    }
    return null;
}
