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

    // Update loop
    try std.Io.sleep(Init.io, .fromSeconds(3), .awake);

    // Deinit
    if (@hasDecl(User, "deinit"))
        User.deinit();
    Engine.deinit();
    std.debug.assert(gpa.deinit() == .ok);
}
