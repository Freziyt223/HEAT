//! Container of all the engine implementations
//! must be initialized like in src/main.zig
const std = @import("std");
const Self = @This();
const Conf = @import("Conf");
const TrackingAllocator = @import("TrackingAllocator");

pub var Allocator: TrackingAllocator = undefined;
pub const IO = @import("IO");
pub const Async = @import("Async");

pub fn init(Io: std.Io, allocator: std.mem.Allocator) !void {
    Allocator = TrackingAllocator.init(allocator, "Global");
    try IO.init(Io);
    try Async.init(Io, Allocator.allocator(), .{ .NumberOfThreads = Conf.NumberOfThreads, .QueueCapacity_EVEN = Conf.QueueCapacity_EVEN });
}
pub fn deinit() void {
    Async.deinit();
}
