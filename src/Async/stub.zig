//! Synchronous compatibility layer used when the Async module is disabled.
const std = @import("std");
pub var required: bool = false;
pub const Config = struct { NumberOfThreads: usize = 0, QueueCapacity_EVEN: usize = 0 };
pub const Scheduler = struct {
    pub const Scheduler = struct {
        pub const Handle = struct {
            id: usize = 0,
            is_canceled: bool = false,
            pub fn cancel(_: *@This()) void {}
        };
    };
};
pub const Reserve = struct {};
pub fn Future(comptime T: type) type {
    if (T == void) @compileError("Future type cannot be void!");
    return struct {
        value: ?T = null,
        pub fn set(self: *@This(), value: T) void {
            self.value = value;
        }
        pub fn tryValue(self: *@This()) ?T {
            return self.value;
        }
        pub fn wait(self: *@This()) T {
            return self.value orelse unreachable;
        }
    };
}
pub fn init(_: std.mem.Allocator, _: Config) !void {}
pub fn deinit() void {}
pub fn call(comptime function: anytype, args: anytype, comptime FutureType: type, result: ?*FutureType) !void {
    const value = @call(.auto, function, args);
    if (FutureType != void) if (result) |f| f.set(value);
}
pub fn callMain(comptime function: anytype, args: anytype, comptime FutureType: type, result: ?*FutureType) !void {
    try call(function, args, FutureType, result);
}
pub fn callMainSync(comptime function: anytype, args: anytype) !ReturnType(function) {
    return @call(.auto, function, args);
}
fn ReturnType(comptime function: anytype) type {
    return @typeInfo(@TypeOf(function)).@"fn".return_type.?;
}
pub fn reserve(_: u16, _: bool) !Reserve {
    return .{};
}
pub fn scheduleRepeated(comptime function: anytype, args: anytype, _: ?std.Io.Duration) !Scheduler.Scheduler.Handle {
    _ = function;
    _ = args;
    return .{};
}
pub fn scheduleOnce(comptime function: anytype, args: anytype, _: std.Io.Timestamp, comptime FutureType: type, result: ?*FutureType) !Scheduler.Scheduler.Handle {
    try call(function, args, FutureType, result);
    return .{};
}
pub fn updateSchedule() !void {}
