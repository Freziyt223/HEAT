//! Entrypoint
const std = @import("std");
const Engine = @import("Engine");
const Conf = @import("Conf");
const User = if (Conf.BuildOptions.has_user) @import("User") else struct {};
comptime {
    _ = @import("C_API");
}

const init = @extern(*const fn () callconv(.c) c_int, .{ .name = "init", .linkage = .weak });
const deinit = @extern(*const fn () callconv(.c) void, .{ .name = "deinit", .linkage = .weak });
const update_func = @extern(*const fn () callconv(.c) c_int, .{ .name = "update_func", .linkage = .weak });
const update_struct = @extern(*const struct { update: *const fn () c_int, tick_rate: c_ulonglong }, .{ .name = "update_struct", .linkage = .weak });
const update_array = @extern(*const []struct { update: *const fn () callconv(.c) c_int, tick_rate: c_ulonglong }, .{ .name = "update_array", .linkage = .weak });

/// This row allows user to pass their own main()
/// it gives full controll but more things to manage
pub const main = if (@hasDecl(User, "main")) User.main else main_impl;
pub fn main_impl(Init: std.process.Init) !void {
    if (@hasDecl(User, "conf"))
        User.conf();
    // Making a globall allocator instance
    var gpa = std.heap.DebugAllocator(.{
        .thread_safe = Conf.BuildOptions.singlethreaded,
        .safety = Conf.BuildOptions.runtime_safety,
    }).init;
    defer std.debug.assert(gpa.deinit() == .ok);

    Engine.IO.Allocator = Engine.TrackingAllocator.init(gpa.allocator(), "IOAllocator");
    var threaded = std.Io.Threaded.init(Engine.IO.Allocator.allocator(), .{});
    const io = threaded.io();

    try Engine.init(io, Conf.GlobalAllocator orelse gpa.allocator());
    defer Engine.deinit();

    if (@hasDecl(User, "init"))
        try User.init(Engine.Init{ .args = Init.minimal.args, .allocator = gpa.allocator() })
    else if (init) |actual_init| {
        const returned = actual_init();
        std.debug.assert(returned == 0);
    }

    defer if (@hasDecl(User, "deinit"))
        User.deinit()
    else if (deinit) |actual_deinit| {
        actual_deinit();
    };

    // Update code, it supports 3 different declarations of update functions and chooses the path
    // instead of checking them each tick
    if (@hasDecl(User, "update")) switch (@typeInfo(@TypeOf(User.update))) {
        .@"fn" => {
            const handle = try Engine.Async.scheduleRepeated(User.update, .{}, null);
            while (Engine.State.load(.acquire) == .Running) {
                try Engine.Async.updateSchedule();
            }
            try handle.cancel();
        },
        // Declaration is pub const update = struct {pub fn update() !void {...}; pub const tick_rate: ?std.Io.Duration = null;}
        .type => {
            if (@hasDecl(User.update, "update")) switch (@typeInfo(@TypeOf(User.update.update))) {
                .@"fn" => {
                    if (@hasDecl(User.update, "tick_rate")) {
                        const handle = try Engine.Async.scheduleRepeated(User.update, .{}, User.update.tick_rate);
                        while (Engine.State.load(.acquire) == .Running) {
                            try Engine.Async.updateSchedule();
                        }
                        try handle.cancel();
                    } else @panic("User update struct has to contain \"tick_rate\" field!");
                },
                else => @panic("update field in User update struct must be a function!"),
            };
        },
        .array => |array| {
            // check for single threaded
            var handles: [array.len]Engine.Async.Scheduler.Scheduler.Handle = undefined;
            inline for (User.update[0..array.len], 0..array.len) |update, i| {
                if (@hasDecl(update, "update")) switch (@typeInfo(@TypeOf(update.update))) {
                    .@"fn" => {
                        if (@hasDecl(update, "tick_rate")) {
                            handles[i] = try Engine.Async.scheduleRepeated(update.update, .{}, update.tick_rate);
                        } else @panic("User update struct has to contain \"tick_rate\" field!");
                    },
                    else => @panic("update field in User update struct must be a function!"),
                };
            }
            while (Engine.State.load(.acquire) == .Running) {
                try Engine.Async.updateSchedule();
            }
            for (handles) |handle| {
                try handle.cancel();
            }
        },
        else => @panic("Wrong type of User update!"),
    };
}
