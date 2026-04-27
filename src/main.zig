//! Entrypoint which assembles user's and engine's code
const std = @import("std");
const User = @import("User");
const Engine = @import("Engine");
const Conf = @import("Conf");

/// Allows user to provide their own main function to be an entrypoint
/// Gives more control but user now should manage the engine for themself
pub const main = if (@hasDecl(User, "main")) User.main else main_impl;
pub fn main_impl(Init: std.process.Init) !void {
    var gpa = std.heap.DebugAllocator(.{
        .thread_safe = Conf.BuildOptions.singlethreaded,
        .safety = Conf.BuildOptions.runtime_safety,
    }).init;

    var engine = Engine{};
    try engine.init(Init.io, Conf.GlobalAllocator orelse gpa.allocator());

    var user = User{};
    try user.init(&engine, Init.minimal.args);
    defer user.deinit();
    


    engine.deinit();
    std.debug.assert(gpa.deinit() == .ok); 
}

// For tests
const TrackingAllocator = @import("TrackingAllocator");
const IO = @import("IO");