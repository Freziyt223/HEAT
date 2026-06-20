const std = @import("std");
const Atomic = std.atomic.Value;
const Task = @import("task.zig");
const Thread = Task.Thread;

pub const FutureError = error{TypeIsVoid};
pub fn Future(comptime T: type) type {
    if (T == void) return FutureError.TypeIsVoid;
    return struct {
        const Self = @This();
        result: ?T = null,
        ready: Atomic(bool) = .init(false),

        pub fn wait(self: *Self) T {
            while (!self.ready.load(.seq_cst)) {
                std.atomic.spinLoopHint();
            }
            return self.result.?;
        }
        pub fn tryValue(self: *Self) ?T {
            return self.result;
        }
        pub fn reset(self: *Self) void {
            self.ready.store(false, .seq_cst);
            self.result = null;
        }
        pub fn set(self: *Self, value: T) void {
            self.result = value;
            self.ready.store(true, .release);
        }
    };
}
