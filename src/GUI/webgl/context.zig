const std = @import("std");
const Interface = @import("Interface");

pub const Context = struct {
    frame_state: std.atomic.Value(Interface.Renderer.FrameState) = .init(.idle),
};

pub var context: Context = .{};
