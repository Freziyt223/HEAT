//! Async is a multithreading wrapper for the engine
const std = @import("std");
const Thread_type = @import("thread.zig");
const TrackingAllocator = @import("TrackingAllocator");
const Atomic = std.atomic.Value;
const Conf = @import("Conf");
const Self = @This();
/// Struct to hold values in queue until needed to be executed
const Call = struct {
    function: *const fn(Call) void,
    args: *anyopaque = undefined,
    return_to: ?*anyopaque
};
pub const Thread = Thread_type.Thread(Call);
pub const JobQueue = Thread.Queue;
/// Struct to hold values for repeated function calling
const ScheduledCall = struct {
    function: *const fn(ScheduledCall) void,
    args: *anyopaque = undefined,
    /// Scheduled time to call the function
    at: std.Io.Timestamp,
    /// Time to wait before calling function next time
    timeout: ?std.Io.Duration = null,
    thread_id: usize
};
/// Queue for scheduler
ScheduleQueue: std.ArrayList(ScheduledCall) = .empty,
Io: std.Io,
/// Thread pool(dirrect calls)
Threads: []Thread = undefined,
running: Atomic(bool) = .init(false),


/// QueueCapacity_Even MUST BE A POWER OF 2
pub const Config = struct {
    NumberOfThreads: usize,
    QueueCapacity_EVEN: usize
};

pub fn init(self: *Self, allocator: std.mem.Allocator, config: Config) !void {
    // Initializing allocators
    Thread.Allocator = TrackingAllocator.init(allocator, "Thread");
    JobQueue.Allocator = TrackingAllocator.init(allocator, "JobQueue");
    // Initializing threads
    self.Threads = try Thread.Allocator.?.allocator().alloc(Thread, config.NumberOfThreads);
    for (self.Threads[0..]) |*thread| {
        thread.* = try Thread.init(config.QueueCapacity_EVEN, self.Threads[0..], &self.running);
        try thread.spawn();
    }
}
pub fn deinit(self: *Self) void {
    self.running.store(false, .release);
    // self.ScheduleQueue.deinit();
    for (self.Threads) |*thread| {
        thread.deinit();
    }
    
    if (Thread.Allocator) |*allocator| allocator.allocator().free(self.Threads);
}

const CallError = error {
    WrongID,
    WrongFunctionType,
};
pub fn call(self: *Self, comptime function: anytype, args: anytype, thread_id: usize) !JobQueue.PushReturn {
    const args_type = @TypeOf(args);
    const stored = if (Thread.Allocator) |*allocator| try allocator.allocator().create(args_type)
                            else return Thread.ThreadError.NullAllocator;
    stored.* = args;
    const item = Call{
        .function = try wrap(function, args_type),
        .args = @ptrCast(@alignCast(stored)),
        .return_to = null
    };
    if (thread_id >= self.Threads.len) return CallError.WrongID;
    return self.Threads[thread_id].queue.push(item);
}

fn wrap(comptime function: anytype, args_type: type) CallError!*const fn(*anyopaque) void {
    const function_type = @TypeOf(function);
    switch (@typeInfo(function_type)) {
        .@"fn" => {
            const wrapper = struct {
                pub fn exec(self: Call) Thread.ThreadError!void {
                    const args = @as(*args_type, self.args);
                    _ = @call(.auto, function, args.*);

                    if (Thread.Allocator) |*allocator| 
                        allocator.allocator().destroy(args);
                }
            };
            return &wrapper.exec;
        },
        else => return error.WrongFunctionType
    }
}
/// WIP don't use for now
pub fn schedule(self: *Self, comptime function: anytype, args: anytype, at: std.Io.Timestamp, thread_id: usize) !void {
    if (thread_id >= self.Threads.len) return CallError.WrongID;
    if (Thread.Allocator) |*allocator| {
        const args_type = @TypeOf(args);
        const stored = try allocator.allocator().create(args_type);
        stored.* = args;
        const item = ScheduledCall{
            .function = try wrap(function, args_type),
            .args = @ptrCast(@alignCast(stored)),
            .thread_id = thread_id,
            .at = at
        };
        
        self.ScheduleQueue.append(allocator.allocator(), item);
    } else return Thread.ThreadError.NullAllocator;
}
/// WIP don't use for now
pub fn scheduleRepeated(self: *Self, comptime function: anytype, args: anytype, timeout: std.Io.Duration, thread_id: usize) !void {
    if (thread_id >= self.Threads.len) return CallError.WrongID;
    if (Thread.Allocator) |*allocator| {
        const args_type = @TypeOf(args);
        const stored = try allocator.allocator().create(args_type);
        stored.* = args;

        const item = ScheduledCall{
            .function = try wrap(function, args_type),
            .args = @ptrCast(@alignCast(stored)),
            .thread_id = thread_id,
            .at = std.Io.Timestamp.now(self.Io, .awake).addDuration(timeout),
            .timeout = timeout,
        };
        
        self.ScheduleQueue.append(allocator.allocator(), item);
    } else return Thread.ThreadError.NullAllocator;
}
/// WIP don't use for now
pub fn updateSchedule(self: *Self) void {
    _ = self;
}