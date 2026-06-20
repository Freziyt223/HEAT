//! Container of all the engine implementations
//! must be initialized like in src/main.zig
const std = @import("std");
const Self = @This();

pub const Conf = @import("Conf");
pub const TrackingAllocator = @import("TrackingAllocator");

pub var Allocator: TrackingAllocator = undefined;
pub const IO = @import("IO");
pub const Async = @import("Async");
pub const ztracy = @import("ztracy");

pub const StateEnum = enum(u8) { Quitting, Running, ErrorQutting };
pub var State: std.atomic.Value(StateEnum) = .init(.Quitting);

pub fn init(Io: std.Io, allocator: std.mem.Allocator) !void {
    Allocator = TrackingAllocator.init(allocator, "Global");
    try IO.init(Io);
    try Async.init(Allocator.allocator(), .{ .NumberOfThreads = Conf.NumberOfThreads, .QueueCapacity_EVEN = Conf.QueueCapacity_EVEN });
    errdefer State.store(.ErrorQutting, .unordered);
    State.store(.Running, .unordered);
}
pub fn deinit() void {
    Async.deinit();
}
