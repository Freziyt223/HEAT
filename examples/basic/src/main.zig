const std = @import("std");
const Self = @This();
const Engine = @import("Engine");
const Conf = @import("Conf");

pub fn init(this: *Self, args: std.process.Args) !void {
    _ = this;
    _ = args;
    try Engine.IO.print("Hello, {s}\n", .{"world!"});
    const returned = try Engine.Async.call(Engine.IO.print, .{ "Hello, {s} From another thread!\n", .{"world!"} }, null);
    // Not ok if queue is full
    if (returned != .ok) {
        std.debug.print("NOT OK!\n", .{});
    }
}
pub fn deinit(this: *Self) void {
    _ = this;
}
