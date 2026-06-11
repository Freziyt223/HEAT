//! Use addExecutable to install your code with engine's
//! To run examples run zig build inside examples folder
const std = @import("std");
pub const Config = @import("config.zig");
/// Configuration of this build
var options: ResolvedOptions = undefined;

const ResolvedOptions = struct {
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    singlethreaded: bool,
    /// False will remove some checks and strip some debug allocator features
    runtime_safety: bool,
    ztracy_enable: bool,
};

fn resolveOptions(b: *std.Build) ResolvedOptions {
    return .{
        .target = b.standardTargetOptions(.{}),
        .optimize = b.option(std.builtin.OptimizeMode, "Optimize", "Select mode which will be used to compile an executable") orelse Config.optimize,
        .singlethreaded = b.option(bool, "singlethreaded", "Specify if engine should be compiled as singlethreaded") orelse Config.singlethreaded,
        .runtime_safety = b.option(bool, "runtime_safety", "Specify if engine should come with runtime data safety checks") orelse Config.runtime_safety,
        .ztracy_enable = b.option(bool, "ztracy", "Specify if program should come with ztracy benchmark tool") orelse Config.ztracy_enable,
    };
}

const ExecutableConfig = struct {
    name: []const u8,
    user_module: *std.Build.Module,

    target: ?std.Build.ResolvedTarget = null,
    optimize: ?std.builtin.OptimizeMode = null,
};

pub fn build(b: *std.Build) void {
    options = resolveOptions(b);
}
pub fn addExecutable(b: *std.Build, config: ExecutableConfig) *std.Build.Step.Compile {
    Config.profile();
    const options_step = b.addOptions();
    options_step.addOption(bool, "singlethreaded", options.singlethreaded);
    options_step.addOption(bool, "runtime_safety", options.runtime_safety);
    // Arguments passed to this build are composed to a module
    // which can be accessed later with just @import
    const BuildOptions = options_step.createModule();

    // Dependencies
    const ztracy = b.dependency("ztracy", .{
        .enable_ztracy = options.ztracy_enable,
    });
    const ztracy_mod = ztracy.module("root");

    // Memory usage tracking
    const TrackingAllocator = b.addModule(
        "TrackingAllocator",
        .{
            .root_source_file = b.path("src/TrackingAllocator.zig"),
            .target = config.target orelse options.target,
            .optimize = config.optimize orelse options.optimize,
        },
    );
    TrackingAllocator.addImport("ztracy", ztracy_mod);

    // Runtime configuration
    const Conf = b.addModule("Conf", .{
        .root_source_file = b.path("src/Conf.zig"),
        .target = config.target orelse options.target,
        .optimize = config.optimize orelse options.optimize,
    });
    config.user_module.addImport("Conf", Conf);
    Conf.addImport("BuildOptions", BuildOptions);

    // Input/Ouput system
    const IO = b.addModule("IO", .{ .root_source_file = b.path("src/IO/main.zig"), .target = config.target orelse options.target, .optimize = config.optimize orelse options.optimize });
    IO.addImport("TrackingAllocator", TrackingAllocator);

    // Async(multithreadong)
    const Async = b.addModule("Async", .{ .root_source_file = b.path("src/Async/main.zig"), .target = config.target orelse options.target, .optimize = config.optimize orelse options.optimize });
    Async.addImport("TrackingAllocator", TrackingAllocator);

    // Engine struct
    const Engine = b.addModule("Engine", .{ .root_source_file = b.path("src/root.zig"), .target = config.target orelse options.target, .optimize = config.optimize orelse options.optimize, .imports = &.{
        .{ .name = "IO", .module = IO },
        .{ .name = "Conf", .module = Conf },
        .{ .name = "TrackingAllocator", .module = TrackingAllocator },
        .{ .name = "Async", .module = Async },
        .{ .name = "ztracy", .module = ztracy_mod },
    } });
    config.user_module.addImport("Engine", Engine);

    // Entrypoint of a final executable
    const Executable = b.addExecutable(.{ .name = config.name, .root_module = b.createModule(.{
        .target = config.target orelse options.target,
        .optimize = config.optimize orelse options.optimize,
        .imports = &.{
            .{ .name = "User", .module = config.user_module },
            .{ .name = "Conf", .module = Conf },
            .{ .name = "Engine", .module = Engine },
            .{ .name = "IO", .module = IO },
            .{ .name = "TrackingAllocator", .module = TrackingAllocator },
        },
        .root_source_file = b.path("src/main.zig"),
    }) });
    Executable.root_module.linkLibrary(ztracy.artifact("tracy"));

    return Executable;
}
