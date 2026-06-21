const std = @import("std");
const IO = @import("IO");
const TrackingAllocator = @import("TrackingAllocator");
const Async = @import("Async");
const Conf = @import("Conf");

pub export fn io_print_backend(str: [*:0]const u8, len: usize) callconv(.c) c_int {
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
    if (!Conf.is_singlethreaded()) {
        const CWorker = struct {
            pub fn exec(self: Async.Task.Call) void {
                const returned = call_helper(self.args);

                if (self.return_to) |out_f| {
                    const f: *C_Future = @ptrCast(@alignCast(out_f));
                    f.set(returned);
                }
            }
            pub fn destroy(self: Async.Task.Call) void {
                if (self.args) |args| {
                    if (self.allocator != null) {
                        self.allocator.?.allocator().destroy(@as(*ctx_struct, @ptrCast(@alignCast(args))));
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
        Async.call_thread_select(item) catch return 1;
        return 0;
    }
    const returned = function(ctx);
    if (target_future) |future| future.set(returned);
    return 0;
}
pub export fn Async_reserve(n: c_ushort, reserve: **anyopaque) callconv(.c) c_int {
    if (Conf.is_singlethreaded()) return @intFromError(Async.Task.ReserveError.Singlethreaded);
    if (n > Async.Threads.len) return @intFromError(Async.Task.ReserveError.OutOfBounds);
    const thread = &Async.Threads[n];
    if (thread.reserved) return @intFromError(Async.Task.ReserveError.AlreadyReserved);
    thread.reserved = true;
    reserve.* = @ptrCast(@alignCast(thread));
    return 0;
}
pub export fn Async_call_reserved(reserve: *anyopaque, function: *const fn (?*anyopaque) callconv(.c) ?*anyopaque, ctx: ?*anyopaque, return_to: ?*anyopaque) callconv(.c) c_int {
    const target_future: ?*C_Future = if (return_to) |ptr| @ptrCast(@alignCast(ptr)) else null;
    if (!Conf.is_singlethreaded()) {
        const CWorker = struct {
            pub fn exec(self: Async.Task.Call) void {
                const returned = call_helper(self.args);

                if (self.return_to) |out_f| {
                    const f: *C_Future = @ptrCast(@alignCast(out_f));
                    f.set(returned);
                }
            }
            pub fn destroy(self: Async.Task.Call) void {
                if (self.args) |args| {
                    if (self.allocator != null) {
                        self.allocator.?.allocator().destroy(@as(*ctx_struct, @ptrCast(@alignCast(args))));
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
        Async.Task.call_thread(@ptrCast(@alignCast(reserve)), item) catch |err| return @intFromError(err);
        return 0;
    }
    const returned = function(ctx);
    if (target_future) |future| future.set(returned);
    return 0;
}
