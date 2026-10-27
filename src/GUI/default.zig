//! Dependency-free no-op GUI API shared with the disabled GUI module.
const std = @import("std");
const TrackingAllocator = @import("TrackingAllocator");

pub const renderer_enum = enum { automatic, vulkan, opengl, directx, bgfx };
pub var Allocator: TrackingAllocator = undefined;
pub var RendererRegistryList: std.SinglyLinkedList = .{ .first = null };

pub const Interface = struct {};

pub fn init(allocator: std.mem.Allocator) !void {
    Allocator = TrackingAllocator.init(allocator, "GUIAllocator");
}
pub fn deinit() void {}
pub fn glfwPollEvents() void {}

pub fn renderer(_: renderer_enum) !?Interface {
    return null;
}

pub fn custom_renderer(_: type) !*Interface {
    return error.NotImplemented;
}

pub const Renderer = struct {
    pub fn Handle(comptime Tag: anytype) type {
        return struct {
            index: u32 = std.math.maxInt(u32),
            generation: u32 = 0,
            pub const tag = Tag;
            pub fn invalid() @This() {
                return .{};
            }
            pub fn isValid(self: @This()) bool {
                return self.index != std.math.maxInt(u32);
            }
        };
    }

    pub const ShaderModule = Handle(.shader_module);
    pub const GraphicsPipeline = Handle(.graphics_pipeline);
    pub const IndexBuffer = Handle(.index_buffer);
    pub const VertexBuffer = Handle(.vertex_buffer);
    pub const DescriptorSetLayout = Handle(.descriptor_set_layout);
    pub const DescriptorPool = Handle(.descriptor_pool);
    pub const DescriptorSet = Handle(.descriptor_set);
    pub const VertexBinding = struct { binding: u32 = 0, stride: u32 = 0, input_rate: VertexInputRate = .vertex };
    pub const VertexAttribute = struct { location: u32 = 0, binding: u32 = 0, format: VertexFormat = .r32_sfloat, offset: u32 = 0 };
    pub const VertexInputRate = enum { vertex, instance };
    pub const VertexFormat = enum { r32_sfloat, r32g32_sfloat, r32g32b32_sfloat, r32g32b32a32_sfloat };
    pub const FrontFace = enum { counter_clockwise, clockwise };
    pub const VertexInputState = struct { bindings: []const VertexBinding = &.{}, attributes: []const VertexAttribute = &.{} };
    pub const GraphicsPipelineCreateInfo = struct {
        vertex_shader: ShaderModule,
        fragment_shader: ShaderModule,
        vertex_input: VertexInputState = .{},
        front_face: FrontFace = .counter_clockwise,
    };
    pub const DescriptorType = enum { uniform_buffer, storage_buffer, sampler, sampled_image, combined_image_sampler, storage_image };
    pub const ShaderStageFlags = packed struct { vertex: bool = false, fragment: bool = false, geometry: bool = false, tessellation_control: bool = false, tessellation_evaluation: bool = false, compute: bool = false };
    pub const DescriptorBinding = struct { binding: u32, descriptor_type: DescriptorType, count: u32 = 1, stages: ShaderStageFlags };
    pub const DescriptorSetLayoutCreateInfo = struct { bindings: []const DescriptorBinding };
    pub const DescriptorPoolSize = struct { descriptor_type: DescriptorType, count: u32 };
    pub const DescriptorPoolCreateInfo = struct { max_sets: u32, pool_sizes: []const DescriptorPoolSize };

    pub fn MakeVertexType(comptime position_num: comptime_int, comptime position_type: type, comptime colour_num: comptime_int, comptime colour_type: type) type {
        return struct {
            position: @Vector(position_num, position_type),
            colour: @Vector(colour_num, colour_type),
            pub fn getBindingDescription() VertexBinding {
                return .{ .stride = @sizeOf(@This()) };
            }
            pub fn getAttributeDescription() [2]VertexAttribute {
                return .{ .{}, .{ .location = 1 } };
            }
        };
    }

    pub const Frame = struct {
        pub fn clear(_: *const Frame, _: [4]f32) !void {}
        pub fn bindPipeline(_: *const Frame, _: GraphicsPipeline) !void {}
        pub fn bindIndexBuffer(_: *const Frame, _: IndexBuffer) !void {}
        pub fn bindVertexBuffer(_: *Frame, _: VertexBuffer) !void {}
        pub fn bindDescriptorSets(_: *const Frame, _: GraphicsPipeline, _: u32, _: []const DescriptorSet) !void {}
        pub fn draw(_: *const Frame, _: u32, _: u32) !void {}
        pub fn end(_: *const Frame) !void {}
        pub fn present(_: *const Frame) !void {}
    };

    pub fn deinit(_: Renderer) void {}
    pub fn beginFrame(_: Renderer) !Frame {
        return .{};
    }
    pub fn createShaderModule(_: Renderer, _: []const u8) !ShaderModule {
        return .invalid();
    }
    pub fn destroyShaderModule(_: Renderer, _: ShaderModule) void {}
    pub fn createGraphicsPipeline(_: *const Renderer, _: GraphicsPipelineCreateInfo) !GraphicsPipeline {
        return .invalid();
    }
    pub fn destroyGraphicsPipeline(_: *const Renderer, _: GraphicsPipeline) void {}
    pub fn createVertexBuffer(_: *const Renderer, comptime T: type, _: []const T) !VertexBuffer {
        return .invalid();
    }
    pub fn destroyVertexBuffer(_: *const Renderer, _: VertexBuffer) void {}
    pub fn createIndexBuffer(_: *const Renderer, comptime T: type, _: []const T) !IndexBuffer {
        return .invalid();
    }
    pub fn destroyIndexBuffer(_: *const Renderer, _: IndexBuffer) void {}
    pub fn createDescriptorSetLayout(_: *const Renderer, _: DescriptorSetLayoutCreateInfo) !DescriptorSetLayout {
        return .invalid();
    }
    pub fn destroyDescriptorSetLayout(_: *const Renderer, _: DescriptorSetLayout) void {}
    pub fn createDescriptorPool(_: *const Renderer, _: DescriptorPoolCreateInfo) !DescriptorPool {
        return .invalid();
    }
    pub fn destroyDescriptorPool(_: *const Renderer, _: DescriptorPool) void {}
    pub fn allocateDescriptorSets(_: *const Renderer, _: DescriptorPool, _: []const DescriptorSetLayout, allocator: std.mem.Allocator) ![]DescriptorSet {
        return allocator.alloc(DescriptorSet, 0);
    }
    pub fn freeDescriptorSets(_: *const Renderer, _: DescriptorPool, _: []const DescriptorSet) !void {}
};

pub const Window = struct {
    pub fn create(_: i32, _: i32, _: [:0]const u8, _: ?*anyopaque, _: ?*anyopaque) !?*Window {
        return &null_window;
    }
    pub fn destroy(_: *Window) void {}
    pub fn shouldClose(_: *Window) bool {
        return true;
    }
    pub fn setupRenderer(_: *Window, _: Interface, _: u32) !Renderer {
        return .{};
    }
};

var null_window: Window = .{};
