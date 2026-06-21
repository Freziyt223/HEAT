const std = @import("std");
const Thread_type = @import("thread.zig");
const TrackingAllocator = @import("TrackingAllocator");
const Atomic = std.atomic.Value;
const Conf = @import("Conf");
const Self = @This();
const Task = @import("task.zig");
const Thread = Task.Thread;
const JobQueue = Task.JobQueue;

pub var Allocator: TrackingAllocator = undefined;

pub const Scheduler = struct {
    pub const SchedulerError = error{ NullAllocator, CallNotFound };
    pub const Handle = struct {
        id: usize,
        pub fn cancel(handle: Handle) !void {
            acquire();
            defer release();
            for (Queue.items, 0..) |item, idx| {
                if (item.id == handle.id) {
                    item.self_destroy(item);
                    _ = Queue.popIndex(idx);
                    return;
                }
            }
            return SchedulerError.CallNotFound;
        }
    };
    pub const Call = struct {
        function: *const fn (Task.Call) void,
        destroy: *const fn (Task.Call) void,
        self_destroy: *const fn (Call) void,
        allocator: ?*TrackingAllocator = null,
        args: ?*anyopaque,
        at: ?std.Io.Timestamp,
        rate: ?std.Io.Duration = null,
        return_to: ?*anyopaque = null,
        id: usize = 0,
    };
    pub var Queue = std.PriorityQueue(Call, void, comparator).empty;
    pub var locked = Atomic(bool).init(false);
    pub var next_call_id = std.atomic.Value(usize).init(0);

    pub fn deinit() void {
        acquire();
        defer release();
        Queue.deinit(Allocator.allocator());
    }

    pub fn push(call: Call) !Handle {
        acquire();
        defer release();
        try Queue.push(Allocator.allocator(), call);
        return Handle{ .id = call.id };
    }

    pub fn nextId() usize {
        return next_call_id.fetchAdd(1, .acq_rel);
    }

    pub fn peek() ?Call {
        acquire();
        defer release();
        return Queue.peek();
    }

    pub fn pop() ?Call {
        acquire();
        defer release();
        return Queue.pop();
    }
    // Simple mutex-like implementation that doesn't block threads but rather makes them busy-wait
    fn acquire() void {
        while (locked.swap(true, .acq_rel)) {
            while (locked.load(.acquire)) std.atomic.spinLoopHint();
        }
    }

    fn release() void {
        locked.store(false, .release);
    }
};

fn comparator(_: void, a: Scheduler.Call, b: Scheduler.Call) std.math.Order {
    if (a.at) |a_at| {
        if (b.at) |b_at| {
            return std.math.order(a_at.nanoseconds, b_at.nanoseconds);
        } else {
            return .gt;
        }
    } else {
        if (b.at) |_| {
            return .lt;
        } else {
            return std.math.order(a.id, b.id);
        }
    }
}
