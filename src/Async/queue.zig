const std = @import("std");
const Atomic = std.atomic.Value;
const TrackingAllocator = @import("TrackingAllocator");

/// MPMC Vyukov's design, uses bitshift operations for blazing fast modulas,
/// which requires capacity to be power of 2
pub fn Queue(comptime ItemType: type) type {
    return struct {
        const Self = @This();
        pub var Allocator: ?TrackingAllocator = null;
        pub const QueueError = error {
            NullAllocator
        };
        pub const PushReturn = enum {
            ok,
            Full
        };
        const Cell = struct {
            sequence: Atomic(usize),
            data: ?ItemType = null
        };

        buffer: []Cell,
        capacity: usize,
        mask: usize,
        ENqueue: Atomic(usize) = .init(0),
        DEqueue: Atomic(usize) = .init(0),

        pub fn init(capacity_EVEN: usize) !Self {
            if (Allocator) |*allocator| {
                const capacity_1 = capacity_EVEN - 1;
                std.debug.assert(capacity_EVEN & capacity_1 == 0);
                const Return = Self{
                    .capacity = capacity_EVEN,
                    .mask = capacity_1,
                    .buffer = try allocator.allocator().alloc(Cell, capacity_EVEN)
                };
                for (0..capacity_EVEN) |i| {
                    Return.buffer[i].sequence.store(i, .unordered);
                }
                return Return;
            } else return error.NullAllocator;
        }
        pub fn deinit(self: *Self) void {
            if (Allocator) |*allocator| {
                allocator.allocator().free(self.buffer);
            }
        }

        pub fn push(self: *Self, item: ItemType) PushReturn {
            var enqueue = self.ENqueue.load(.acquire);

            while (true) {
                const cell = &self.buffer[enqueue & self.mask];
                // Safe subtract(as we cast to isize we lose first bit, which isn't very important as we only need range from -1 to 1)
                const diff = @as(isize, @bitCast(cell.sequence.load(.acquire) -% enqueue));
                if (diff > 0) {
                    // Some thread was ahead of us, try again
                    enqueue += 1;
                    continue;
                }
                else if (diff < 0) {
                    // Other thread is working on this object or full queue
                    if (enqueue & self.mask == 0) return PushReturn.Full;
                    // if it's other thread try again
                    continue;
                }

                // Try to write the value and check again if other thread was ahead of us
                if (self.ENqueue.cmpxchgWeak(enqueue, enqueue +% 1, .monotonic, .monotonic)) |actual_enqueue| {
                    // FAILED: Another thread swooped in and grabbed this ticket
                    // 'actual_enqueue' holds the new value of ENqueue. Update this local variable and retry.
                    enqueue = actual_enqueue;
                    continue;
                }
                cell.data = item;
                cell.sequence.store(enqueue +% 1, .release);
                return PushReturn.ok;
            } 
        }

        pub fn pop(self: *Self) ?ItemType {
            var dequeue = self.DEqueue.load(.acquire);
            
            while (true) {
                const cell = &self.buffer[dequeue & self.mask];
                const sequence = cell.sequence.load(.acquire);
                // Safe subtract(as we cast to isize we lose first bit, which isn't very important as we only need range from -1 to 1)
                const diff = @as(isize, @bitCast(sequence -% (dequeue +% 1)));
                if (diff < 0) {
                    // Empty
                    return null;
                }
                else if (diff > 0) {
                    dequeue = self.DEqueue.load(.monotonic);
                }

                // Try to return the value and check again if other thread was ahead of us
                if (self.DEqueue.cmpxchgWeak(dequeue, dequeue +% 1, .monotonic, .monotonic)) |actual_dequeue| {
                    // FAILED: Another thread swooped in and grabbed this ticket
                    // 'actual_enqueue' holds the new value of ENqueue. Update this local variable and retry.
                    dequeue = actual_dequeue;
                    continue;
                }
                // Updating sequence to be 
                cell.sequence.store(dequeue +% self.capacity, .release);
                const item = cell.data;

                return item;
            }
        }
    };
}