const std = @import("std");
const Thread_type = @import("thread.zig");
const TrackingAllocator = @import("TrackingAllocator");
const Atomic = std.atomic.Value;
const Conf = @import("Conf");
const Future = @import("Future.zig");
const Self = @This();
/// Struct to hold values in queue until needed to be executed
pub const Call = struct {
    function: *const fn (Call) void,
    destroy: *const fn (*const Call) void,
    allocator: ?*TrackingAllocator = null,
    args: ?*anyopaque,
    return_to: ?*anyopaque = null,
};
pub const Thread = Thread_type.Thread(Call, Reserve);
pub const JobQueue = Thread.Queue;
/// I've made this struct to merge general calls and thread-reserved calls
/// Generally this should allow users to access threads directly,
/// pin them so random calls won't be called in it
pub const Reserve = struct {
    thread: *Thread,
    pub fn call(self: *Reserve, item: Call) !JobQueue.PushReturn {
        return self.thread.queue.push(item);
    }
};

const CallError = error{
    WrongID,
    WrongFunctionType,
};
pub fn wrap(comptime function: anytype, args_type: type, CallType: type) CallError!struct {
    exec: *const fn (CallType) void,
    destroy: *const fn (*const CallType) void,
} {
    const function_type = @TypeOf(function);
    switch (@typeInfo(function_type)) {
        .@"fn" => {
            // Using the wrapper to place a function declaration inside this wrap() function
            const wrapper = struct {
                pub fn exec(self: CallType) void {
                    // 1. We use inline if (or a comptime block just for the type logic)
                    // to decide *how* to initialize the tuple at runtime.
                    const args_tuple = if (comptime args_type == void)
                        .{}
                    else
                        @as(*args_type, @ptrCast(@alignCast(self.args orelse unreachable))).*;

                    // 2. Call the function once
                    const returned = @call(.auto, function, args_tuple);

                    // 3. Handle the return value/future
                    if (self.return_to) |self_return_to| {
                        const return_to: *Future.Future(@TypeOf(returned)) = @ptrCast(@alignCast(self_return_to));
                        return_to.set(returned);
                    }
                }
                pub fn destroy(self: *const CallType) void {
                    if (self.allocator) |allocator| {
                        if (self.args) |args_stored| {
                            const args = @as(*args_type, @ptrCast(@alignCast(args_stored)));
                            allocator.allocator().destroy(args);
                        }
                    }
                }
            };
            return .{ .exec = wrapper.exec, .destroy = wrapper.destroy };
        },
        .pointer => |p| {
            switch (@typeInfo(p.child)) {
                .@"fn" => {
                    // Using the wrapper to place a function declaration inside this wrap() function
                    const wrapper = struct {
                        pub fn exec(self: CallType) void {
                            const returned = @call(.auto, function, if (self.args) |args| @as(*args_type, @ptrCast(@alignCast(args))).* else .{});
                            if (self.return_to) |self_return_to| {
                                const return_to: *Future.Future(@TypeOf(returned)) = @ptrCast(@alignCast(self_return_to));
                                return_to.set(returned);
                            }
                        }
                        pub fn destroy(self: *const CallType) void {
                            if (self.allocator) |allocator| {
                                if (self.args) |args_stored| {
                                    const args = @as(*args_type, @ptrCast(@alignCast(args_stored)));
                                    allocator.allocator().destroy(args);
                                }
                            }
                        }
                    };
                    return .{ .exec = wrapper.exec, .destroy = wrapper.destroy };
                },
                else => return error.WrongFunctionType,
            }
        },
        else => return error.WrongFunctionType,
    }
}

pub fn null_destroy(_: *const Call) void {}
