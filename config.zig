const std = @import("std");

pub var optimize: std.builtin.OptimizeMode = .Debug;
pub var singlethreaded: bool = false;
pub var runtime_safety: bool = true;
pub var profile: *const fn () void = &default_profile;
pub var ztracy_enable: bool = true;

pub var c_bindings: bool = true;
pub var use_lua: bool = true;

pub fn default_profile() void {}
