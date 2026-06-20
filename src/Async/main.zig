//! Async is a multithreading wrapper for the engine
const std = @import("std");
const Thread_type = @import("thread.zig");
const TrackingAllocator = @import("TrackingAllocator");
const IO = @import("IO");
const Atomic = std.atomic.Value;
const Conf = @import("Conf");
const Self = @This();
pub const Task = @import("task.zig");
pub const Scheduler = @import("scheduler.zig");
const scheduler = Scheduler.Scheduler;
pub const Thread = Task.Thread;
pub const JobQueue = Task.JobQueue;

/// Thread pool(dirrect calls)
pub var Threads: []Task.Thread = undefined;
pub var running: Atomic(bool) = .init(true);

pub var next_thread: usize = 0;

/// QueueCapacity_Even MUST BE A POWER OF 2
pub const Config = struct { NumberOfThreads: usize, QueueCapacity_EVEN: usize };

pub fn init(allocator: std.mem.Allocator, config: Config) !void {
    // Initializing allocators
    Thread.Allocator = TrackingAllocator.init(allocator, "Thread");
    JobQueue.Allocator = TrackingAllocator.init(allocator, "JobQueue");
    Scheduler.Allocator = TrackingAllocator.init(JobQueue.Allocator.allocator(), "SchedulerAllocator");
    // Initializing threads
    if (!Conf.is_singlethreaded()) {
        Threads = try Thread.Allocator.allocator().alloc(Thread, config.NumberOfThreads);
        for (Threads[0..]) |*thread| {
            thread.* = try Thread.init(config.QueueCapacity_EVEN, Threads[0..], &running);
            try thread.spawn();
        }
    }
}
pub fn deinit() void {
    running.store(false, .release);
    scheduler.deinit();
    if (!Conf.is_singlethreaded()) {
        for (Threads) |*thread| {
            thread.deinit();
        }

        Thread.Allocator.allocator().free(Threads);
    }
}

const CallError = error{
    WrongID,
    WrongFunctionType,
};
pub fn call(comptime function: anytype, args: anytype, FutureType: type, return_to: ?*FutureType) !JobQueue.PushReturn {
    if (!Conf.is_singlethreaded()) {
        // Just wanted to try using blocks in zig...
        const item = item_blk: {
            const Allocator = &JobQueue.Allocator;
            const args_type = @TypeOf(args);
            const wrapper = try Task.wrap(function, args_type, Task.Call);
            break :item_blk Task.Call{
                .function = wrapper.exec,
                .destroy = wrapper.destroy,
                .allocator = Allocator,
                .args = args_blk: {
                    switch (@typeInfo(args_type)) {
                        .optional => {
                            if (args) |args_actual| {
                                const allocator = Allocator.allocator();
                                const stored = try allocator.create(args_type);
                                stored.* = args_actual;
                                break :args_blk stored;
                            } else break :args_blk null;
                        },
                        else => {
                            const allocator = Allocator.allocator();
                            const stored = try allocator.create(args_type);
                            stored.* = args;
                            break :args_blk stored;
                        },
                    }
                },
                .return_to = if (return_to) |address| @ptrCast(@alignCast(address)) else null,
            };
        };
        const capacity = Threads.len;
        var iterations = capacity;
        var i = @mod(next_thread, capacity);
        var thread = &Threads[i];
        while (thread.reserved and iterations != 0) {
            next_thread +%= 1;
            iterations -= 1;
            if (i >= capacity) i = 0;
            i = @mod(next_thread, capacity);
            thread = &Threads[i];
        }
        next_thread = i +% 1;
        var reserve = Task.Reserve{ .thread = thread };

        return reserve.call(item);
    }
    const returned = @call(.auto, function, args);
    if (FutureType != void) if (return_to) |future| future.set(returned);
    return .ok;
}

pub fn scheduleRepeated(comptime function: anytype, args: anytype, rate: ?std.Io.Duration) !scheduler.Handle {
    const Allocator = &Scheduler.Allocator;
    const args_type = @TypeOf(args);
    const wrapper = try Task.wrap(function, args_type, Task.Call);
    const self_wrapper = try Task.wrap(function, args_type, scheduler.Call);
    const args_stored = try Allocator.allocator().create(args_type);
    args_stored.* = args;

    const item = scheduler.Call{
        .function = wrapper.exec,
        .destroy = wrapper.destroy,
        .self_destroy = self_wrapper.destroy,
        .allocator = Allocator,
        .args = args_stored,
        .rate = rate,
        .at = if (rate) |rt| std.Io.Timestamp.now(IO.io, .awake).addDuration(rt) else null,
        .id = scheduler.nextId(),
    };
    return scheduler.push(item);
}

pub fn scheduleOnce(comptime function: anytype, args: anytype, at: std.Io.Timestamp, FutureType: type, return_to: ?*FutureType) !scheduler.Handle {
    const Allocator = &Scheduler.Allocator;
    const args_type = @TypeOf(args);
    const wrapper = try Task.wrap(function, args_type, Task.Call);
    const self_wrapper = try Task.wrap(function, args_type, scheduler.Call);
    const args_stored = try Allocator.allocator().create(args_type);
    args_stored.* = args;

    const item = scheduler.Call{
        .function = wrapper.exec,
        .destroy = wrapper.destroy,
        .self_destroy = self_wrapper.destroy,
        .allocator = Allocator,
        .args = args_stored,
        .at = at,
        .return_to = if (return_to) |address| @ptrCast(@alignCast(address)) else null,
        .id = scheduler.nextId(),
    };
    return scheduler.push(item);
}

pub fn cancelSchedule(handle: scheduler.Handle) !void {
    return Scheduler.Scheduler.Handle.cancel(handle);
}

pub fn updateSchedule() !void {
    while (true) {
        const now = std.Io.Timestamp.now(IO.io, .awake);
        const maybe_item = scheduler.peek();
        if (maybe_item == null) break;

        const item = maybe_item.?;
        if (item.at) |at| {
            if (now.nanoseconds < at.nanoseconds) break;
        }

        _ = scheduler.pop();

        if (item.rate) |r| {
            var new_item = item;
            new_item.at = now.addDuration(r);
            new_item.id = scheduler.nextId();
            _ = try scheduler.push(new_item);
        }
        const call_item = Task.Call{
            .function = item.function,
            .destroy = if (item.rate != null) &Task.null_destroy else item.destroy,
            .args = item.args,
            .return_to = item.return_to,
        };
        if (!Conf.is_singlethreaded()) {
            const capacity = Threads.len;
            var iterations = capacity;
            var i = @mod(next_thread, capacity);
            var thread = &Threads[i];
            while (thread.reserved and iterations != 0) {
                next_thread +%= 1;
                iterations -= 1;
                if (i >= capacity) i = 0;
                thread = &Threads[i];
            }
            next_thread = i +% 1;
            var reserve = Task.Reserve{ .thread = thread };

            _ = try reserve.call(call_item);
        } else {
            call_item.function(call_item);
            if (item.at == null) item.self_destroy(&item);
        }
    }
}

pub const Future = @import("Future.zig").Future;
