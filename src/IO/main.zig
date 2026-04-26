//! IO wrapper for file and console manipulations
const std = @import("std");
const Self = @This();

const TrackingAllocator = @import("TrackingAllocator");

io: std.Io = undefined,

pub fn init(IO: std.Io) !Self {
    return Self{
        .io = IO,
    };
}
pub fn deinit(self: *Self) void {
    _ = self;
}

pub fn print(this: Self, comptime fmt: []const u8, args: anytype) !void {
    var buf: [1024]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(this.io, buf[0..]);
    try stdout_writer.interface.print(fmt, args);
    try stdout_writer.interface.flush();
}
pub fn read(this: Self, buf: []u8) !void {
    const internal_buf: [1024]u8 = undefined;
    var stdin_reader = std.Io.File.stdin().reader(this.io, internal_buf[0..]);
    stdin_reader.interface.readSliceAll(buf) catch |err| switch(err) {
        .ReadFailed => return err,
        .EndOfStream => return
    };
}