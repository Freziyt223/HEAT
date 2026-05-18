const std = @import("std");
const Self = @This();
const Engine = @import("Engine");
const Conf = @import("Conf");

pub fn init(this: *Self, engine: *Engine, args: std.process.Args) !void {
    _ = this;
    _ = args;
    try engine.IO.print("Hello, {s}\n", .{"world!"});
}
pub fn deinit(this: *Self) void {
    _ = this;
}