//! Entrypoint
const std = @import("std");
const User = @import("User");
const Engine = @import("Engine");
const Conf = @import("Conf");

/// This row allows user to pass their own main()
/// it gives full controll but more things to manage
pub const main = if (@hasDecl(User, "main")) User.main else main_impl;
pub fn main_impl(Init: std.process.Init) !void {
    // Making a globall allocator instance
    var gpa = std.heap.DebugAllocator(.{
        .thread_safe = Conf.BuildOptions.singlethreaded,
        .safety = Conf.BuildOptions.runtime_safety,
    }).init;

    // Making an engine object
    try Engine.init(Init.io, Conf.GlobalAllocator orelse gpa.allocator());
    if (@hasDecl(User, "init"))
        try User.init(Init.minimal.args);

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

    // Deinit
    if (@hasDecl(User, "deinit"))
        User.deinit();
    Engine.deinit();
    std.debug.assert(gpa.deinit() == .ok);
}
