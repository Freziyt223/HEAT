const std = @import("std");
const Interface = @import("Interface");
const host = @import("host.zig");
const Renderer = Interface.Renderer;

fn handle(comptime T: type, id: u32) T {
    return .{ .index = id, .generation = 1 };
}

pub fn createShaderModule(_: *anyopaque, source: []const u8) !Renderer.ShaderModule {
    return handle(Renderer.ShaderModule, host.shader_create(source.ptr, source.len));
}
pub fn destroyShaderModule(_: *anyopaque, shader: Renderer.ShaderModule) void {
    if (shader.isValid()) host.shader_destroy(shader.index);
}

pub fn createGraphicsPipeline(_: *anyopaque, info: Renderer.GraphicsPipelineCreateInfo) !Renderer.GraphicsPipeline {
    var stride: u32 = 20;
    var position_offset: u32 = 0;
    var colour_offset: u32 = 8;
    if (info.vertex_input.bindings.len > 0) stride = info.vertex_input.bindings[0].stride;
    for (info.vertex_input.attributes) |attribute| {
        if (attribute.location == 0) position_offset = attribute.offset;
        if (attribute.location == 1) colour_offset = attribute.offset;
    }
    const id = host.pipeline_create(info.vertex_shader.index, info.fragment_shader.index, stride, position_offset, colour_offset);
    return handle(Renderer.GraphicsPipeline, id);
}
pub fn destroyGraphicsPipeline(_: *anyopaque, pipeline: Renderer.GraphicsPipeline) void {
    if (pipeline.isValid()) host.pipeline_destroy(pipeline.index);
}

pub fn createVertexBuffer(_: *anyopaque, bytes: []const u8) !Renderer.VertexBuffer {
    return handle(Renderer.VertexBuffer, host.buffer_create(bytes.ptr, bytes.len, false));
}
pub fn destroyVertexBuffer(_: *anyopaque, buffer: Renderer.VertexBuffer) void {
    if (buffer.isValid()) host.buffer_destroy(buffer.index, false);
}
pub fn bindVertexBuffer(_: *anyopaque, buffer: Renderer.VertexBuffer) !void {
    host.bind_buffer(buffer.index, false);
}

pub fn createIndexBuffer(_: *anyopaque, bytes: []const u8) !Renderer.IndexBuffer {
    return handle(Renderer.IndexBuffer, host.buffer_create(bytes.ptr, bytes.len, true));
}
pub fn destroyIndexBuffer(_: *anyopaque, buffer: Renderer.IndexBuffer) void {
    if (buffer.isValid()) host.buffer_destroy(buffer.index, true);
}
pub fn bindIndexBuffer(_: *anyopaque, buffer: Renderer.IndexBuffer) !void {
    host.bind_buffer(buffer.index, true);
}

pub fn createDescriptorSetLayout(_: *anyopaque, _: Renderer.DescriptorSetLayoutCreateInfo) !Renderer.DescriptorSetLayout {
    return error.Unsupported;
}
pub fn destroyDescriptorSetLayout(_: *anyopaque, _: Renderer.DescriptorSetLayout) void {}
pub fn createDescriptorPool(_: *anyopaque, _: Renderer.DescriptorPoolCreateInfo) !Renderer.DescriptorPool {
    return error.Unsupported;
}
pub fn destroyDescriptorPool(_: *anyopaque, _: Renderer.DescriptorPool) void {}
pub fn allocateDescriptorSets(_: *anyopaque, _: Renderer.DescriptorPool, _: []const Renderer.DescriptorSetLayout, _: std.mem.Allocator) ![]Renderer.DescriptorSet {
    return error.Unsupported;
}
pub fn freeDescriptorSets(_: *anyopaque, _: Renderer.DescriptorPool, _: []const Renderer.DescriptorSet) !void {
    return error.Unsupported;
}
pub fn bindDescriptorSets(_: *anyopaque, _: Renderer.GraphicsPipeline, _: u32, _: []const Renderer.DescriptorSet) !void {
    return error.Unsupported;
}
