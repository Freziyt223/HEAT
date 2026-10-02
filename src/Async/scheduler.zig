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

pub const CallQueue = struct {
    buffer: []Scheduler.Call = &.{},
    items: []Scheduler.Call = &.{},
    len: usize = 0,
    capacity: usize = 0,

    pub fn deinit(self: *CallQueue, allocator: std.mem.Allocator) void {
        if (self.capacity > 0) {
            for (self.items) |item| {
                item.self_destroy(item);
            }
            allocator.free(self.buffer);
        }
        self.* = .{};
    }

    pub fn ensureCapacity(self: *CallQueue, allocator: std.mem.Allocator, new_capacity: usize) !void {
        if (new_capacity <= self.capacity) return;
        var cap = if (self.capacity == 0) 8 else self.capacity * 2;
        if (cap < new_capacity) cap = new_capacity;
        const new_buffer = try allocator.alloc(Scheduler.Call, cap);
        if (self.len > 0) {
            @memcpy(new_buffer[0..self.len], self.buffer[0..self.len]);
        }
        if (self.capacity > 0) {
            allocator.free(self.buffer);
        }
        self.buffer = new_buffer;
        self.capacity = cap;
        self.items = self.buffer[0..self.len];
    }

    pub fn push(self: *CallQueue, allocator: std.mem.Allocator, call: Scheduler.Call) !void {
        try self.ensureCapacity(allocator, self.len + 1);
        self.buffer[self.len] = call;
        self.len += 1;
        self.items = self.buffer[0..self.len];
        self.siftUp(self.len - 1);
    }

    pub fn peek(self: CallQueue) ?Scheduler.Call {
        if (self.len == 0) return null;
        return self.buffer[0];
    }

    pub fn peekPtr(self: *CallQueue) ?*Scheduler.Call {
        if (self.len == 0) return null;
        return &self.buffer[0];
    }

    pub fn pop(self: *CallQueue) ?Scheduler.Call {
        if (self.len == 0) return null;
        const res = self.buffer[0];
        self.len -= 1;
        if (self.len > 0) {
            self.buffer[0] = self.buffer[self.len];
            self.items = self.buffer[0..self.len];
            self.siftDown(0);
        } else {
            self.items = self.buffer[0..0];
        }
        return res;
    }

    pub fn rescheduleTop(self: *CallQueue, new_at: ?std.Io.Timestamp, tick: usize) void {
        if (self.len == 0) return;
        self.buffer[0].at = new_at;
        self.buffer[0].last_tick = tick;
        self.siftDown(0);
    }

    pub fn removeIndex(self: *CallQueue, index: usize) ?Scheduler.Call {
        if (index >= self.len) return null;
        const item = self.buffer[index];
        self.len -= 1;
        if (index < self.len) {
            self.buffer[index] = self.buffer[self.len];
            self.items = self.buffer[0..self.len];
            self.siftDown(index);
            self.siftUp(index);
        } else {
            self.items = self.buffer[0..self.len];
        }
        return item;
    }

    pub fn removeById(self: *CallQueue, id: usize) ?Scheduler.Call {
        for (0..self.len) |i| {
            if (self.buffer[i].id == id) {
                return self.removeIndex(i);
            }
        }
        return null;
    }

    pub fn heapify(self: *CallQueue) void {
        if (self.len <= 1) return;
        var i: usize = self.len / 2;
        while (i > 0) {
            i -= 1;
            self.siftDown(i);
        }
    }

    pub fn updateOrder(self: *CallQueue) void {
        self.heapify();
    }

    fn siftUp(self: *CallQueue, start_index: usize) void {
        var index = start_index;
        while (index > 0) {
            const parent = (index - 1) / 2;
            if (!less(self.buffer[index], self.buffer[parent])) {
                break;
            }
            self.swap(index, parent);
            index = parent;
        }
    }

    fn siftDown(self: *CallQueue, start_index: usize) void {
        var index = start_index;
        while (true) {
            const left = index * 2 + 1;
            if (left >= self.len) break;
            const right = left + 1;
            var smallest = left;
            if (right < self.len and less(self.buffer[right], self.buffer[left])) {
                smallest = right;
            }
            if (!less(self.buffer[smallest], self.buffer[index])) {
                break;
            }
            self.swap(index, smallest);
            index = smallest;
        }
    }

    fn swap(self: *CallQueue, a: usize, b: usize) void {
        const tmp = self.buffer[a];
        self.buffer[a] = self.buffer[b];
        self.buffer[b] = tmp;
    }
};

pub const Scheduler = struct {
    pub const SchedulerError = error{ NullAllocator, CallNotFound };

    pub const Handle = struct {
        id: usize,
        is_canceled: bool = false,

        pub fn cancel(self: *Handle) void {
            if (self.is_canceled) return;
            if (Scheduler.cancel(self.id)) {
                self.is_canceled = true;
            }
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
        is_repeated: bool = false,
        last_tick: usize = 0,
        setup: ?*const fn (call: *Task.Call, thread_id: usize) void = null,
    };

    pub var Queue: CallQueue = .{};
    pub var locked = Atomic(bool).init(false);
    pub var next_call_id = std.atomic.Value(usize).init(0);
    pub var current_tick: usize = 0;

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

    pub fn rescheduleTop(new_at: ?std.Io.Timestamp, tick: usize) void {
        acquire();
        defer release();
        Queue.rescheduleTop(new_at, tick);
    }

    pub fn count() usize {
        acquire();
        defer release();
        return Queue.len;
    }

    pub fn cancel(id: usize) bool {
        acquire();
        defer release();
        if (Queue.removeById(id)) |item| {
            item.self_destroy(item);
            return true;
        }
        return false;
    }

    pub fn updateOrder() void {
        acquire();
        defer release();
        Queue.updateOrder();
    }

    fn acquire() void {
        while (locked.swap(true, .acq_rel)) {
            while (locked.load(.acquire)) std.atomic.spinLoopHint();
        }
    }

    fn release() void {
        locked.store(false, .release);
    }
};

pub fn less(a: Scheduler.Call, b: Scheduler.Call) bool {
    if (a.at) |a_at| {
        if (b.at) |b_at| {
            if (a_at.nanoseconds != b_at.nanoseconds) {
                return a_at.nanoseconds < b_at.nanoseconds;
            }
            return a.id < b.id;
        } else {
            return false;
        }
    } else {
        if (b.at) |_| {
            return true;
        } else {
            return a.id < b.id;
        }
    }
}
