const std = @import("std");

pub var optimize: std.builtin.OptimizeMode = .Debug;
pub var singlethreaded: bool = false;
pub var runtime_safety: bool = true;
pub var profile: *const fn () void = &default_profile;
pub var ztracy_enable: bool = true;

pub var c_bindings: bool = true;
pub var use_lua: bool = true;

pub const Dependencies = struct {
    pub const zgui = struct {
        pub var shared: bool = false;
    };
};
pub var build_vulkan: bool = true;
pub var build_opengl: bool = false;
pub var build_directx: bool = false;
pub const renderer_enum = enum { automatic, vulkan, opengl, directx };
pub var renderer: renderer_enum = .vulkan;

pub fn default_profile() void {}
