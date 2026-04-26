//! If null is specified standart configurations will be applied including build options or standart values
//! If you want to change this do it with caution as it may break some things
const std = @import("std");
pub const BuildOptions = @import("BuildOptions");

pub var runtime_safety: ?bool = null;
pub var GlobalAllocator: ?std.mem.Allocator = null;