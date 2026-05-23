//! Async is a multithreading wrapper for the engine
const std = @import("std");
const Thread_type = @import("thread.zig");
const TrackingAllocator = @import("TrackingAllocator");
const Atomic = std.atomic.Value;
const Conf = @import("Conf");
const Self = @This();
/// Struct to hold values in queue until needed to be executed
const Call = struct {
    function: *const fn (Call) void,
    args: *anyopaque,
    return_to: ?*anyopaque = null,
};
pub const Thread = Thread_type.Thread(Call, Reserve);
pub const JobQueue = Thread.Queue;
/// I've made this struct to merge general calls and thread-reserved calls
/// Generally this should allow users to access threads directly,
/// pin them so random calls won't be called in it
pub const Reserve = struct {
    thread: *Thread,
    pub fn call(self: *Reserve, comptime function: anytype, args: anytype, return_to: ?*anyopaque) !JobQueue.PushReturn {
        // Just wanted to try using blocks in zig...
        const item = item_blk: {
            if (Thread.Allocator) |*Allocator| {
                const allocator = Allocator.allocator();
                const args_type = @TypeOf(args);
                const wrap_function = try wrap(function, args_type);
                const stored = try allocator.create(args_type);
                stored.* = args;
                break :item_blk Call{ .function = wrap_function, .args = @ptrCast(@alignCast(stored)), .return_to = return_to };
            } else return Thread.ThreadError.NullAllocator;
        };
        return self.thread.queue.push(item);
    }
};
pub var Io: std.Io = undefined;
/// Thread pool(dirrect calls)
pub var Threads: []Thread = undefined;
pub var running: Atomic(bool) = .init(true);

pub var next_thread: usize = 0;

/// QueueCapacity_Even MUST BE A POWER OF 2
pub const Config = struct { NumberOfThreads: usize, QueueCapacity_EVEN: usize };

pub fn init(io: std.Io, allocator: std.mem.Allocator, config: Config) !void {
    Io = io;
    // Initializing allocators
    Thread.Allocator = TrackingAllocator.init(allocator, "Thread");
    JobQueue.Allocator = TrackingAllocator.init(allocator, "JobQueue");
    // Initializing threads
    Threads = try Thread.Allocator.?.allocator().alloc(Thread, config.NumberOfThreads);
    for (Threads[0..]) |*thread| {
        thread.* = try Thread.init(config.QueueCapacity_EVEN, Threads[0..], &running);
        try thread.spawn();
    }
}
pub fn deinit() void {
    running.store(false, .release);
    // self.ScheduleQueue.deinit();
    for (Threads) |*thread| {
        thread.deinit();
    }

    if (Thread.Allocator) |*allocator| allocator.allocator().free(Threads);
}

const CallError = error{
    WrongID,
    WrongFunctionType,
};
pub fn call(comptime function: anytype, args: anytype, return_to: ?*anyopaque) !JobQueue.PushReturn {
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
    var reserve = Reserve{ .thread = thread };
    return reserve.call(function, args, return_to);
}

fn wrap(comptime function: anytype, args_type: type) CallError!*const fn (Call) void {
    const function_type = @TypeOf(function);
    switch (@typeInfo(function_type)) {
        .@"fn" => {
            // Using the wrapper to place a function declaration inside this wrap() function
            const wrapper = struct {
                pub fn exec(self: Call) void {
                    const args = @as(*args_type, @ptrCast(@alignCast(self.args)));
                    _ = @call(.auto, function, args.*) catch {};

                    if (Thread.Allocator) |*allocator|
                        allocator.allocator().destroy(args);
                }
            };
            return &wrapper.exec;
        },
        else => return error.WrongFunctionType,
    }
}
