const std = @import("std");
const IO = @import("IO");
const TrackingAllocator = @import("TrackingAllocator");
const Async = @import("Async");

export fn io_print_backend(str: [*c]const u8, len: usize) callconv(.c) c_int {
    const slice = str[0..len];
    IO.print("{s}", .{slice}) catch |err| return @intFromError(err);
    return 0;
}
pub export fn IO_read(buf: *u8, len: usize) callconv(.c) c_ulonglong {
    const slice = @as([]u8, @ptrCast(@alignCast(buf)))[0..len];
    return IO.read(slice) catch |err| return @intFromError(err);
}

pub export fn Async_updateSchedule() callconv(.c) c_int {
    Async.updateSchedule() catch |err| return @intFromError(err);
    return 0;
}

const C_Future = Async.Future(?*anyopaque);

pub export fn Async_FutureCreate() callconv(.c) ?*anyopaque {
    const Allocator = &Async.JobQueue.Allocator;
    const alloc = Allocator.allocator();

    const f = alloc.create(C_Future) catch return null;
    f.* = .{
        .result = null,
        .ready = std.atomic.Value(bool).init(false),
    };
    return f;
}

pub export fn Async_FutureDestroy(future_ptr: ?*anyopaque) callconv(.c) void {
    const Allocator = &Async.JobQueue.Allocator;
    const alloc = Allocator.allocator();
    if (future_ptr) |ptr| {
        const f: *C_Future = @ptrCast(@alignCast(ptr));
        alloc.destroy(f);
    }
}

pub export fn Async_FutureWait(future_ptr: ?*anyopaque) callconv(.c) ?*anyopaque {
    const ptr = future_ptr orelse return null;
    const f: *C_Future = @ptrCast(@alignCast(ptr));
    // Твій метод wait() повертає !T. Оскільки помилки тут малоймовірні, робимо catch
    return f.wait();
}
pub export fn Async_FutureSet(future_ptr: ?*anyopaque, value: ?*anyopaque) callconv(.c) c_int {
    const ptr = future_ptr orelse return @intFromBool(false);
    const f: *C_Future = @ptrCast(@alignCast(ptr));
    f.set(value);
    return @intFromBool(true);
}
const ctx_struct = struct {
    function: *const fn (?*anyopaque) callconv(.c) ?*anyopaque,
    ctx: ?*anyopaque,
};
fn call_helper(full_ctx: ?*anyopaque) ?*anyopaque {
    if (full_ctx) |ctx| {
        const casted_ctx: *ctx_struct = @ptrCast(@alignCast(ctx));
        return casted_ctx.function(casted_ctx.ctx);
    }
    return null;
}
pub export fn Async_call(function: *const fn (?*anyopaque) callconv(.c) ?*anyopaque, ctx: ?*anyopaque, return_to: ?*anyopaque) callconv(.c) c_int {
    const target_future: ?*C_Future = if (return_to) |ptr| @ptrCast(@alignCast(ptr)) else null;
    const CWorker = struct {
        pub fn exec(self: Async.Task.Call) void {
            const returned = call_helper(self.args);

            if (self.return_to) |out_f| {
                const f: *C_Future = @ptrCast(@alignCast(out_f));
                f.set(returned);
            }
        }
        pub fn destroy(self: *const Async.Task.Call) void {
            if (self.args) |args| {
                if (self.allocator) |*Allocator| {
                    Allocator.*.allocator().destroy(@as(*ctx_struct, @ptrCast(@alignCast(args))));
                }
            }
        }
    };
    const Allocator = &Async.JobQueue.Allocator;
    const full_ctx = Allocator.allocator().create(ctx_struct) catch |err| return @intFromError(err);
    full_ctx.* = ctx_struct{
        .function = function,
        .ctx = ctx,
    };
    const item = Async.Task.Call{
        .function = CWorker.exec,
        .destroy = CWorker.destroy,
        .allocator = Allocator,
        .args = @ptrCast(@alignCast(full_ctx)),
        .return_to = if (target_future) |address| @ptrCast(@alignCast(address)) else null,
    };
    const capacity = Async.Threads.len;
    var iterations = capacity;
    var i = @mod(Async.next_thread, capacity);
    var thread = &Async.Threads[i];
    while (thread.reserved and iterations != 0) {
        Async.next_thread +%= 1;
        iterations -= 1;
        if (i >= capacity) i = 0;
        i = @mod(Async.next_thread, capacity);
        thread = &Async.Threads[i];
    }
    Async.next_thread = i +% 1;
    var reserve = Async.Task.Reserve{ .thread = thread };

    const returned = reserve.call(item) catch |err| return @intFromError(err);
    return @intFromEnum(returned);
}
