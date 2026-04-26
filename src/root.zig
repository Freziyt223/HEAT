//! This is main header of the engine, when imported
//! it contains generic types and definitions.
//! When passed as built object it contains actual
//! implementations
const std = @import("std");
const Self = @This();
const IO_type = @import("IO");
const Conf = @import("Conf");
const TrackingAllocator = @import("TrackingAllocator");

Allocator: TrackingAllocator = undefined,
IO: IO_type = undefined,

pub fn init(self: *Self, Io: std.Io, allocator: std.mem.Allocator) !void {
    self.Allocator = .init(allocator, "Global");
    self.IO = try IO_type.init(Io);
}
pub fn deinit(self: *Self) void {
    _ = self;
}