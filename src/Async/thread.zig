const std = @import("std");
const Atomic = std.atomic.Value;
pub const queue = @import("queue.zig");
const TrackingAllocator = @import("TrackingAllocator");

pub fn Thread(comptime itemType: type, comptime Reserve: type) type {
    return struct {
        const Self = @This();
        pub var Allocator: TrackingAllocator = undefined;
        pub const Queue = queue.Queue(itemType);

        handle: std.Thread = undefined,
        queue: Queue,
        //Not used for now
        //cache: []u1,
        active: std.atomic.Value(bool) = .init(false),

        /// This is external array of threads so we can use steal() on them
        thread_pool: []Self,
        running: *Atomic(bool),
        reserved: bool = false,

        /// Initializing thread and queue
        /// queueCapacity_EVEN has to be a power of 2
        pub fn init(capacity_EVEN: usize, thread_pool: []Self, running: *Atomic(bool)) !Self {
            return Self{ .queue = try .init(capacity_EVEN), .thread_pool = thread_pool, .running = running, .active = .init(true) };
        }
        pub fn deinit(self: *Self) void {
            self.handle.join();
            self.queue.deinit();
        }
        /// Spawn a thread
        pub fn spawn(self: *Self) !void {
            self.handle = try std.Thread.spawn(.{ .allocator = Allocator.allocator() }, worker, .{self});
        }
        /// Function that will process the queue on a new thread
        pub fn worker(self: *Self) void {
            while (self.running.load(.seq_cst) and self.active.load(.acquire)) {
                if (self.queue.pop()) |call| {
                    call.function(call);
                    call.destroy(call);
                } else {
                    std.atomic.spinLoopHint();
                }
            }
            self.active.store(false, .release);
        }

        pub fn getHandle(self: *Self) Reserve {
            return Reserve{ .thread = self };
        }

        pub fn reserve(self: *Self) Reserve {
            self.reserved = true;
            return Reserve{ .thread = self };
        }
    };
}
