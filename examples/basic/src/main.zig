const std = @import("std");
const Self = @This();
const Engine = @import("Engine");
const Conf = @import("Conf");

pub fn init(args: std.process.Args) !void {
    _ = args;
    try Engine.IO.print("Hello, {s}\n", .{"world!"});
    const returned = try Engine.Async.call(Engine.IO.print, .{ "Hello, {s} From another thread!\n", .{"world!"} }, void, null);
    // Not ok if queue is full
    if (returned != .ok) {
        std.debug.print("NOT OK!\n", .{});
    }
}

pub const update = [_]type{
    struct {
        pub fn update() !void {
            const Zone = Engine.ztracy.ZoneN(@src(), "120 HZ");
            defer Zone.End();
            //try Engine.IO.print("Ticking on 120 tps!\n", .{});
        }
        // 120 ticks per second(hz)
        pub const tick_rate: ?std.Io.Duration = .fromMicroseconds(8333);
    },
    struct {
        pub fn update() !void {
            const Zone = Engine.ztracy.ZoneN(@src(), "60 HZ");
            defer Zone.End();
            //try Engine.IO.print("Ticking on 60 tps!\n", .{});
        }
        // 60 ticks per second(hz)
        pub const tick_rate: ?std.Io.Duration = .fromMicroseconds(16667);
    },
};

pub fn deinit() void {}
