//! For now only uses vulkan with glfw and no interface
const std = @import("std");
const builtin = @import("builtin");
const TrackingAllocator = @import("TrackingAllocator");
const Async = @import("Async");
const Conf = @import("Conf");
pub const Interface = @import("Interface");
const zglfw = @import("zglfw");
const zgui = @import("zgui");

// Renderers
const vulkan = @import("vulkan");
// const dx11 = @import("dx11");
pub const renderer_enum = enum {
    automatic,
    vulkan,
    opengl,
    directx,
    bgfx,
};
pub var Allocator: TrackingAllocator = undefined;
pub var RendererRegistryList: std.SinglyLinkedList = .{ .first = null };
const RendererRegistry = struct {
    renderer: Interface,
    node: std.SinglyLinkedList.Node,
};

fn registerRenderer(interface: Interface) !*Interface {
    const allocator = Allocator.allocator();

    const registry = try allocator.create(RendererRegistry);

    registry.* = .{
        .renderer = interface,
        .node = .{},
    };

    RendererRegistryList.prepend(&registry.node);

    return &registry.renderer;
}

pub fn renderer(implementation: renderer_enum) !?Interface {
    switch (implementation) {
        .vulkan => {
            const interface = vulkan.getInterface();
            try interface.init(Allocator.allocator());
            _ = try registerRenderer(interface);

            return interface;
        },

        else => {
            return null;
        },
    }
}

pub fn custom_renderer(implementation: type) !*Interface {
    const interface = Interface{
        .init = implementation.init,
        .deinit = implementation.deinit,
    };

    return try registerRenderer(interface);
}

pub fn init(allocator: std.mem.Allocator) !void {
    Allocator = TrackingAllocator.init(allocator, "GUIAllocator");
}
pub fn deinit() void {
    const allocator = Allocator.allocator();

    while (RendererRegistryList.popFirst()) |item| {
        const registry: *RendererRegistry =
            @fieldParentPtr("node", item);
        registry.renderer.deinit();
        allocator.destroy(registry);
    }
}

pub const Window = Interface.Window;
pub const Renderer = Interface.Renderer;
pub fn glfwPollEvents() void {
    zglfw.pollEvents();
}
