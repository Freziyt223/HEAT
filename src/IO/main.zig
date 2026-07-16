//! IO wrapper
const std = @import("std");
const Self = @This();

const TrackingAllocator = @import("TrackingAllocator");
pub var Allocator: TrackingAllocator = undefined;

pub var Io: std.Io = undefined;

pub fn init(IO: std.Io) !void {
    Io = IO;
}
pub fn deinit() void {}

pub fn print(comptime fmt: []const u8, args: anytype) std.Io.Writer.Error!void {
    var buf: [1024]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(Io, buf[0..]);
    try stdout_writer.interface.print(fmt, args);
    try stdout_writer.interface.flush();
}
pub fn read(buf: []u8) std.Io.Reader.Error!usize {
    var internal_buf: [1024]u8 = undefined;
    var stdin_reader = std.Io.File.stdin().reader(Io, internal_buf[0..1024]);
    return stdin_reader.interface.readSliceShort(buf);
}
pub fn warn(comptime fmt: []const u8, args: anytype, err: anyerror) std.Io.Writer.Error!void {
    var buf: [1024]u8 = undefined;
    var stdout_writer = std.Io.File.stderr().writer(Io, buf[0..]);
    try stdout_writer.interface.print(fmt, args);
    try stdout_writer.interface.print("Error name: {}\n", .{@errorName(err)});
    try stdout_writer.interface.flush();
    if (@errorReturnTrace()) |trace| {
        std.debug.dumpStackTrace(trace);
    }
}
