const std = @import("std");
const Engine = @import("Engine");
const Conf = @import("Conf");

pub fn init(Init: Engine.Init) !void {
    var interator = try Init.args.iterateAllocator(Init.allocator);
    _ = interator.skip();
}
pub fn deinit() void {}
