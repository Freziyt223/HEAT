//! JavaScript imports implemented by the browser host page.
extern "env" fn heat_web_canvas_init(width: u32, height: u32) void;
extern "env" fn heat_web_clear(r: f32, g: f32, b: f32, a: f32) void;
extern "env" fn heat_web_shader_create(source: [*]const u8, length: usize) u32;
extern "env" fn heat_web_shader_destroy(shader: u32) void;
extern "env" fn heat_web_pipeline_create(vertex: u32, fragment: u32, stride: u32, position_offset: u32, colour_offset: u32) u32;
extern "env" fn heat_web_pipeline_destroy(pipeline: u32) void;
extern "env" fn heat_web_buffer_create(data: [*]const u8, length: usize, index_buffer: bool) u32;
extern "env" fn heat_web_buffer_destroy(buffer: u32, index_buffer: bool) void;
extern "env" fn heat_web_bind_pipeline(pipeline: u32) void;
extern "env" fn heat_web_bind_buffer(buffer: u32, index_buffer: bool) void;
extern "env" fn heat_web_draw(index_count: u32, instance_count: u32) void;
extern "env" fn heat_web_canvas_deinit() void;

pub const canvas_init = heat_web_canvas_init;
pub const clear = heat_web_clear;
pub const shader_create = heat_web_shader_create;
pub const shader_destroy = heat_web_shader_destroy;
pub const pipeline_create = heat_web_pipeline_create;
pub const pipeline_destroy = heat_web_pipeline_destroy;
pub const buffer_create = heat_web_buffer_create;
pub const buffer_destroy = heat_web_buffer_destroy;
pub const bind_pipeline = heat_web_bind_pipeline;
pub const bind_buffer = heat_web_bind_buffer;
pub const draw = heat_web_draw;
pub const canvas_deinit = heat_web_canvas_deinit;
