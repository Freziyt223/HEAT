//! Async is a multithreading wrapper for the engine
const std = @import("std");
const Thread_type = @import("thread.zig");
const TrackingAllocator = @import("TrackingAllocator");
const Atomic = std.atomic.Value;
const Conf = @import("Conf");
const Self = @This();
const Task = @import("task.zig");
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

pub fn init(io: std.Io, allocator: std.mem.Allocator, config: Config) !void {
    Thread.Io = io;
    // Initializing allocators
    Thread.Allocator = TrackingAllocator.init(allocator, "Thread");
    JobQueue.Allocator = TrackingAllocator.init(allocator, "JobQueue");
    Scheduler.Allocator = TrackingAllocator.init(allocator, "SchedulerAllocator");
    // Initializing threads
    Threads = try Thread.Allocator.?.allocator().alloc(Thread, config.NumberOfThreads);
    for (Threads[0..]) |*thread| {
        thread.* = try Thread.init(config.QueueCapacity_EVEN, Threads[0..], &running);
        try thread.spawn();
    }
}
pub fn deinit() void {
    running.store(false, .release);
    scheduler.deinit();
    for (Threads) |*thread| {
        thread.deinit();
    }

    if (Thread.Allocator) |*allocator| allocator.allocator().free(Threads);
}

const CallError = error{
    WrongID,
    WrongFunctionType,
};
pub fn call(comptime function: anytype, args: anytype, FutureType: type, return_to: ?*FutureType) !JobQueue.PushReturn {
    // Just wanted to try using blocks in zig...
    const item = item_blk: {
        if (Thread.Allocator) |*Allocator| {
            const allocator = Allocator.allocator();
            const args_type = @TypeOf(args);
            const wrapper = try Task.wrap(function, args_type, Task.Call);
            const stored = try allocator.create(args_type);
            stored.* = args;
            break :item_blk Task.Call{
                .function = wrapper.exec,
                .destroy = wrapper.destroy,
                .allocator = Allocator,
                .args = @ptrCast(@alignCast(stored)),
                .return_to = if (return_to) |address| @ptrCast(@alignCast(address)) else null,
            };
        } else return Thread.ThreadError.NullAllocator;
    };
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

    return reserve.call(item);
}

pub fn scheduleRepeated(comptime function: anytype, args: anytype, rate: ?std.Io.Duration) !scheduler.Handle {
    if (Scheduler.Allocator) |*allocator| {
        const args_type = @TypeOf(args);
        const wrapper = try Task.wrap(function, args_type, Task.Call);
        const self_wrapper = try Task.wrap(function, args_type, scheduler.Call);
        const args_stored = try allocator.allocator().create(args_type);
        args_stored.* = args;

        const item = scheduler.Call{
            .function = wrapper.exec,
            .destroy = wrapper.destroy,
            .self_destroy = self_wrapper.destroy,
            .allocator = allocator,
            .args = args_stored,
            .rate = rate,
            .at = if (rate) |rt| std.Io.Timestamp.now(Thread.Io, .awake).addDuration(rt) else null,
            .id = scheduler.nextId(),
        };
        return scheduler.push(item);
    } else return scheduler.SchedulerError.NullAllocator;
}

pub fn scheduleOnce(comptime function: anytype, args: anytype, at: std.Io.Timestamp, FutureType: type, return_to: ?*FutureType) !scheduler.Handle {
    if (Scheduler.Allocator) |*allocator| {
        const args_type = @TypeOf(args);
        const wrapper = try Task.wrap(function, args_type);
        const self_wrapper = try Task.wrap(function, args_type, scheduler.Call);
        const args_stored = try allocator.allocator().create(args_type);
        args_stored.* = args;

        const item = scheduler.Call{
            .function = wrapper.exec,
            .destroy = wrapper.destroy,
            .self_destroy = self_wrapper.destroy,
            .allocator = allocator,
            .args = args_stored,
            .at = at,
            .return_to = if (return_to) |address| @ptrCast(@alignCast(address)) else null,
            .id = scheduler.nextId(),
        };
        return scheduler.push(item);
    } else return scheduler.SchedulerError.NullAllocator;
}

pub fn cancelSchedule(handle: scheduler.Handle) !void {
    return Scheduler.Scheduler.Handle.cancel(handle);
}

pub fn updateSchedule() !void {
    while (true) {
        const now = std.Io.Timestamp.now(Thread.Io, .awake);
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
    }
}
