//! Memory tracking wrapper around std.mem.Allocator,
//! it uses atomic monotonic mode for multithreading
const std = @import("std");

const Self = @This();
/// This is the internal vtable of this allocator
const inner_struct = struct {
    Allocated: std.atomic.Value(usize),
    AllocationCount: std.atomic.Value(usize),
    FreeCount: std.atomic.Value(usize),
    Peak: std.atomic.Value(usize),
    Category: [*:0]const u8,
};
inner: inner_struct,
InternalAllocator: std.mem.Allocator,

pub fn Allocated(self: Self) usize {
    return self.inner.Allocated.load(.monotonic);
}
pub fn Peak(self: Self) usize {
    return self.inner.Peak.load(.monotonic);
}
pub fn AllocationCount(self: Self) usize {
    return self.inner.AllocationCount.load(.monotonic);
}
pub fn FreeCount(self: Self) usize {
    return self.inner.FreeCount.load(.monotonic);
}
pub fn Category(self: Self) [*:0]const u8 {
    return self.inner.Category;
}
const tracking_vtable = std.mem.Allocator.VTable{
    .alloc = alloc,
    .resize = resize,
    .free = free,
    .remap = remap,
};

pub fn init(Allocator: std.mem.Allocator, category: [*:0]const u8) Self {
    return .{ .InternalAllocator = Allocator, .inner = .{ .Category = category, .Allocated = .{ .raw = 0 }, .AllocationCount = .{ .raw = 0 }, .FreeCount = .{ .raw = 0 }, .Peak = .{ .raw = 0 } } };
}

pub fn allocator(self: *Self) std.mem.Allocator {
    return .{
        .ptr = self,
        .vtable = &tracking_vtable,
    };
}

fn shouldTrack(self: *Self) bool {
    return self.InternalAllocator.vtable != &tracking_vtable;
}

fn alloc(state: *anyopaque, len: usize, alignment: std.mem.Alignment, ret_addr: usize) ?[*]u8 {
    const self: *Self = @ptrCast(@alignCast(state));

    const res = self.InternalAllocator.vtable.alloc(
        self.InternalAllocator.ptr,
        len,
        alignment,
        ret_addr,
    );

    if (!shouldTrack(self)) return res;

    if (res) |_| {
        const new_allocated = self.inner.Allocated.fetchAdd(len, .monotonic) + len;
        _ = self.inner.AllocationCount.fetchAdd(1, .monotonic);

        // оновлюємо Peak
        var peak = self.inner.Peak.load(.monotonic);
        while (new_allocated > peak) : (peak = self.inner.Peak.load(.monotonic)) {
            if (self.inner.Peak.cmpxchgStrong(peak, new_allocated, .monotonic, .monotonic)) |_| break;
        }
    }

    return res;
}

fn free(state: *anyopaque, buf: []u8, alignment: std.mem.Alignment, ret_addr: usize) void {
    const self: *Self = @ptrCast(@alignCast(state));

    self.InternalAllocator.vtable.free(
        self.InternalAllocator.ptr,
        buf,
        alignment,
        ret_addr,
    );

    if (!shouldTrack(self)) return;

    _ = self.inner.Allocated.fetchSub(buf.len, .monotonic);
    _ = self.inner.FreeCount.fetchAdd(1, .monotonic);
}

fn resize(state: *anyopaque, buf: []u8, alignment: std.mem.Alignment, new_len: usize, ret_addr: usize) bool {
    const self: *Self = @ptrCast(@alignCast(state));

    const ok = self.InternalAllocator.vtable.resize(
        self.InternalAllocator.ptr,
        buf,
        alignment,
        new_len,
        ret_addr,
    );

    if (!ok) return false;
    if (!shouldTrack(self)) return true;

    if (new_len > buf.len) {
        const diff = new_len - buf.len;
        const new_allocated = self.inner.Allocated.fetchAdd(diff, .monotonic) + diff;
        _ = self.inner.AllocationCount.fetchAdd(1, .monotonic);

        // оновлюємо Peak
        var peak = self.inner.Peak.load(.monotonic);
        while (new_allocated > peak) : (peak = self.inner.Peak.load(.monotonic)) {
            if (self.inner.Peak.cmpxchgStrong(peak, new_allocated, .monotonic, .monotonic)) |_| break;
        }
    } else if (new_len < buf.len) {
        const diff = buf.len - new_len;
        _ = self.inner.Allocated.fetchSub(diff, .monotonic);
        _ = self.inner.FreeCount.fetchAdd(1, .monotonic);
        _ = self.inner.AllocationCount.fetchSub(1, .monotonic);
    }

    return true;
}

fn remap(state: *anyopaque, buf: []u8, alignment: std.mem.Alignment, new_len: usize, ret_addr: usize) ?[*]u8 {
    const self: *Self = @ptrCast(@alignCast(state));

    const res = self.InternalAllocator.vtable.remap(
        self.InternalAllocator.ptr,
        buf,
        alignment,
        new_len,
        ret_addr,
    );

    if (!shouldTrack(self)) return res;

    if (res) |_| {
        if (new_len > buf.len) {
            const diff = new_len - buf.len;
            const new_allocated = self.inner.Allocated.fetchAdd(diff, .monotonic) + diff;
            _ = self.inner.AllocationCount.fetchAdd(1, .monotonic);

            // оновлюємо Peak
            var peak = self.inner.Peak.load(.monotonic);
            while (new_allocated > peak) : (peak = self.inner.Peak.load(.monotonic)) {
                if (self.inner.Peak.cmpxchgStrong(peak, new_allocated, .monotonic, .monotonic)) |_| break;
            }
        } else if (new_len < buf.len) {
            const diff = buf.len - new_len;
            _ = self.inner.Allocated.fetchSub(diff, .monotonic);
            _ = self.inner.FreeCount.fetchAdd(1, .monotonic);
            _ = self.inner.AllocationCount.fetchSub(1, .monotonic);
        }
    }

    return res;
}
