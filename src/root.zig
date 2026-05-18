//! Container of all the engine implementations
//! must be initialized like in src/main.zig
const std = @import("std");
const Self = @This();
const IO_type = @import("IO");
const Async_type = @import("Async");
const Conf = @import("Conf");
const TrackingAllocator = @import("TrackingAllocator");

Allocator: TrackingAllocator = undefined,
IO: IO_type = undefined,
Async: Async_type = .{},

pub fn init(self: *Self, Io: std.Io, allocator: std.mem.Allocator) !void {
    self.Allocator = .init(allocator, "Global");
    self.IO = try IO_type.init(Io);
    try self.Async.init(self.Allocator.allocator(), .{ .NumberOfThreads = Conf.NumberOfThreads, .QueueCapacity_EVEN = Conf.QueueCapacity_EVEN });
}
pub fn deinit(self: *Self) void {
    self.Async.deinit();
}