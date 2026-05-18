//! Система побудови двигуна,
//! використовуєте addExecutable(...) для отримання з'єднаної програми двигуна та вашого коду
const std = @import("std");
pub const Config = @import("config.zig");
var options: ResolvedOptions = undefined;

pub fn build(b: *std.Build) void {
    options = resolveOptions(b);
    const example = b.createModule(.{
        .root_source_file = b.path("src/example.zig"),
        .target = options.target,
        .optimize = options.optimize,
    });

    // створення прикладної програми з src/example.zig
    const exe = addExecutable(b, .{ 
        .name = "Example", 
        .user_module = example,
    });

    // Steps
    // zig build run
    const run_cmd = b.addRunArtifact(exe);

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the application");
    run_step.dependOn(&run_cmd.step);

    // zig build examples

    b.installArtifact(exe);
}

const ResolvedOptions = struct {
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    singlethreaded: bool,
    runtime_safety: bool,
};

fn resolveOptions(b: *std.Build) ResolvedOptions {
    return .{ 
        .target = b.standardTargetOptions(.{}), 
        .optimize = b.option(std.builtin.OptimizeMode, "Optimize", "Select mode which will be used to compile an executable") orelse Config.optimize, 
        .singlethreaded = b.option(bool, "singlethreaded", "Specify if engine should be compiled as singlethreaded") orelse Config.singlethreaded, 
        .runtime_safety = b.option(bool, "runtime_safety", "Specify if engine should come with runtime data safety checks") orelse Config.runtime_safety 
    };
}

const ExecutableConfig = struct {
    name: []const u8,
    user_module: *std.Build.Module,

    target: ?std.Build.ResolvedTarget = null,
    optimize: ?std.builtin.OptimizeMode = null,
};

pub fn addExecutable(b: *std.Build, config: ExecutableConfig) *std.Build.Step.Compile {
    Config.profile();
    const options_step = b.addOptions();
    options_step.addOption(bool, "singlethreaded", options.singlethreaded);
    options_step.addOption(bool, "runtime_safety", options.runtime_safety);
    // Агрументи передані до даного скрипта побудови зібрані як модуль який можна
    // використовувати всередині програми
    const BuildOptions = options_step.createModule();

    // Спостерігання за пам'яттю
    const TrackingAllocator = b.addModule("TrackingAllocator", .{ 
        .root_source_file = b.path("src/TrackingAllocator.zig"), 
        .target = config.target orelse options.target, 
        .optimize = config.optimize orelse options.optimize 
    });

    // Конфігурація для двигуна
    const Conf = b.addModule("Conf", .{
        .root_source_file = b.path("src/Conf.zig"),
        .target = config.target orelse options.target,
        .optimize = config.optimize orelse options.optimize,
    });
    config.user_module.addImport("Conf", Conf);
    Conf.addImport("BuildOptions", BuildOptions);
    
    // Система ввводу та виводу даних для програми
    const IO = b.addModule("IO", .{ 
        .root_source_file = b.path("src/IO/main.zig"), 
        .target = config.target orelse options.target, 
        .optimize = config.optimize orelse options.optimize 
    });
    IO.addImport("TrackingAllocator", TrackingAllocator);

    // Async(багатопоточність) для двигуна
    const Async = b.addModule("Async", .{
        .root_source_file = b.path("src/Async/main.zig"),
        .target = config.target orelse options.target,
        .optimize = config.optimize orelse options.optimize 
    });
    Async.addImport("TrackingAllocator", TrackingAllocator);

    // Основна обгортка що об'єднує в собі інші
    const Engine = b.addModule("Engine", .{ 
        .root_source_file = b.path("src/root.zig"), 
        .target = config.target orelse options.target, 
        .optimize = config.optimize orelse options.optimize, 
        .imports = &.{ 
            .{ .name = "IO", .module = IO }, 
            .{ .name = "Conf", .module = Conf }, 
            .{ .name = "TrackingAllocator", .module = TrackingAllocator },
            .{ .name = "Async", .module = Async }
        } 
    });
    config.user_module.addImport("Engine", Engine);

    // Виконувана програма
    const Executable = b.addExecutable(.{ .name = config.name, .root_module = b.createModule(.{
        .target = config.target orelse options.target,
        .optimize = config.optimize orelse options.optimize,
        .imports = &.{ .{ .name = "User", .module = config.user_module }, .{ .name = "Conf", .module = Conf }, .{ .name = "Engine", .module = Engine }, .{ .name = "IO", .module = IO }, .{ .name = "TrackingAllocator", .module = TrackingAllocator } },
        .root_source_file = b.path("src/main.zig"),
    }) });

    resolveDependencies(b, Executable);

    return Executable;
}

fn resolveDependencies(b: *std.Build, Exe: *std.Build.Step.Compile) void {
    _ = b;
    _ = Exe;
}