const Interface = @import("Interface");
const host = @import("host.zig");
const Context = @import("context.zig").Context;

fn get(ctx: *anyopaque) *Context {
    return @ptrCast(@alignCast(ctx));
}

pub fn beginFrame(ctx: *anyopaque, frame: *Interface.Renderer.Frame) !void {
    frame.state = &get(ctx).frame_state;
}
pub fn clear(_: *anyopaque, colour: [4]f32) !void {
    host.clear(colour[0], colour[1], colour[2], colour[3]);
}
pub fn bindPipeline(_: *anyopaque, pipeline: Interface.Renderer.GraphicsPipeline) !void {
    host.bind_pipeline(pipeline.index);
}
pub fn bindVertexBuffer(_: *anyopaque, buffer: Interface.Renderer.VertexBuffer) !void {
    host.bind_buffer(buffer.index, false);
}
pub fn bindIndexBuffer(_: *anyopaque, buffer: Interface.Renderer.IndexBuffer) !void {
    host.bind_buffer(buffer.index, true);
}
pub fn draw(_: *anyopaque, index_count: u32, instance_count: u32) !void {
    host.draw(index_count, instance_count);
}
pub fn endFrame(_: *anyopaque) !void {}
pub fn present(_: *anyopaque) !void {}
