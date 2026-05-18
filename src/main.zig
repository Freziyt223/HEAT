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
    var engine = Engine{};
    try engine.init(Init.io, Conf.GlobalAllocator orelse gpa.allocator());

    // and an user object
    var user = User{};
    try user.init(&engine, Init.minimal.args);
    defer user.deinit();

    // Update loop

    

    // Deinit
    engine.deinit();
    std.debug.assert(gpa.deinit() == .ok); 
}