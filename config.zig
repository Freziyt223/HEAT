const std = @import("std");

pub var optimize: std.builtin.OptimizeMode = .Debug;
pub var singlethreaded: bool = false;
pub var runtime_safety: bool = true;
pub var profile: *const fn () void = &default_profile;
pub var ztracy_enable: bool = true;

pub var c_bindings: bool = true;
pub var use_lua: bool = true;
pub var use_glfw: bool = true;
pub var gui: bool = true;

pub const Dependencies = struct {
    pub const zgui = struct {
        pub var shared: bool = false;
    };
};
pub var build_vulkan: bool = true;
pub var build_opengl: bool = false;
pub var build_directx: bool = false;
pub const renderer_enum = enum { automatic, vulkan, opengl, directx, bgfx, none };
pub var renderer: renderer_enum = .vulkan;

/// Targets produced when `-Dmultitarget=true` is enabled. Each query must set
/// both `os_tag` and `cpu_arch`.
var target_buffer: [2]std.Target.Query = .{
    .{ .cpu_arch = .x86_64, .os_tag = .windows },
    .{ .cpu_arch = .x86_64, .os_tag = .linux },
};
pub var targets: std.ArrayList(std.Target.Query) = blk: {
    var list = std.ArrayList(std.Target.Query).initBuffer(&target_buffer);
    list.items = &target_buffer;
    break :blk list;
};
pub var multitarget: bool = true;

pub fn default_profile() void {}
