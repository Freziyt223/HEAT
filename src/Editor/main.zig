const std = @import("std");
const Engine = @import("Engine");
const Conf = @import("Conf");
var Allocator: Engine.TrackingAllocator = undefined;

pub fn init(Init: Engine.Init) !void {
    _ = Init;
    // TODO editor with lua
}

pub fn deinit() void {}
