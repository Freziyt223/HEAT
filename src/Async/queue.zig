const std = @import("std");
const Atomic = std.atomic.Value;
const TrackingAllocator = @import("TrackingAllocator");

/// MPMC Vyukov's design, uses bitshift operations for blazing fast modulas,
/// which requires capacity to be power of 2
pub fn Queue(comptime ItemType: type) type {
    return struct {
        const Self = @This();
        pub var Allocator: TrackingAllocator = undefined;
        pub const QueueError = error{NullAllocator};
        pub const PushReturn = enum { ok, Full };
        const Cell = struct { sequence: Atomic(usize), data: ?ItemType = null };

        buffer: []Cell,
        capacity: usize,
        mask: usize,
        ENqueue: Atomic(usize) = .init(0),
        DEqueue: Atomic(usize) = .init(0),

        pub fn init(capacity_EVEN: usize) !Self {
            const capacity_1 = capacity_EVEN - 1;
            std.debug.assert(capacity_EVEN & capacity_1 == 0);
            const Return = Self{ .capacity = capacity_EVEN, .mask = capacity_1, .buffer = try Allocator.allocator().alloc(Cell, capacity_EVEN) };
            for (0..capacity_EVEN) |i| {
                Return.buffer[i].sequence.store(i, .unordered);
            }
            return Return;
        }
        pub fn deinit(self: *Self) void {
            Allocator.allocator().free(self.buffer);
        }
        pub const PushError = error{Full};
        pub fn push(self: *Self, item: ItemType) PushError!void {
            var enqueue = self.ENqueue.load(.monotonic);

            while (true) {
                const cell = &self.buffer[enqueue & self.mask];
                const sequence = cell.sequence.load(.acquire);
                const diff = @as(isize, @bitCast(sequence -% enqueue));

                if (diff == 0) {
                    if (self.ENqueue.cmpxchgWeak(enqueue, enqueue +% 1, .monotonic, .monotonic)) |actual_enqueue| {
                        enqueue = actual_enqueue;
                        continue;
                    }
                    cell.data = item;
                    cell.sequence.store(enqueue +% 1, .release);
                    return;
                } else if (diff < 0) {
                    return PushError.Full;
                } else {
                    enqueue = self.ENqueue.load(.monotonic);
                }
            }
        }

        pub fn pop(self: *Self) ?ItemType {
            var dequeue = self.DEqueue.load(.monotonic);

            while (true) {
                const cell = &self.buffer[dequeue & self.mask];
                const sequence = cell.sequence.load(.acquire);
                const diff = @as(isize, @bitCast(sequence -% (dequeue +% 1)));

                if (diff == 0) {
                    if (self.DEqueue.cmpxchgWeak(dequeue, dequeue +% 1, .monotonic, .monotonic)) |actual_dequeue| {
                        dequeue = actual_dequeue;
                        continue;
                    }
                    const item = cell.data;
                    cell.data = null;

                    cell.sequence.store(dequeue +% self.capacity, .release);
                    return item;
                } else if (diff < 0) {
                    return null;
                } else {
                    dequeue = self.DEqueue.load(.monotonic);
                }
            }
        }
    };
}
