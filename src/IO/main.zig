//! IO wrapper
const std = @import("std");
const Self = @This();

const TrackingAllocator = @import("TrackingAllocator");

pub var io: std.Io = undefined;

pub fn init(IO: std.Io) !void {
    io = IO;
}
pub fn deinit() void {}

pub fn print(comptime fmt: []const u8, args: anytype) !void {
    var buf: [1024]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(io, buf[0..]);
    try stdout_writer.interface.print(fmt, args);
    try stdout_writer.interface.flush();
}
pub fn read(buf: []u8) !void {
    const internal_buf: [1024]u8 = undefined;
    var stdin_reader = std.Io.File.stdin().reader(io, internal_buf[0..]);
    stdin_reader.interface.readSliceAll(buf) catch |err| switch (err) {
        .ReadFailed => return err,
        .EndOfStream => return,
    };
}
