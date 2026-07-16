//! Use addExecutable to install your code with engine's
//! To run examples run zig build inside examples folder
const std = @import("std");
pub const Config = @import("config.zig");
/// Configuration of this build
var options: ?ResolvedOptions = null;

const ResolvedOptions = struct {
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    singlethreaded: bool,
    /// False will remove some checks and strip some debug allocator features
    runtime_safety: bool,
    ztracy_enable: bool,
    c_bindings: bool,
    use_lua: bool,
    zgui_shared: bool,
    build_vulkan: bool,
    build_opengl: bool,
    build_directx: bool,
    renderer: Config.renderer_enum,
};

fn resolveOptions(b: *std.Build) ResolvedOptions {
    return .{
        .target = b.standardTargetOptions(.{}),
        .optimize = b.option(std.builtin.OptimizeMode, "Optimize", "Select mode which will be used to compile an executable") orelse Config.optimize,
        .singlethreaded = b.option(bool, "singlethreaded", "Specify if engine should be compiled as singlethreaded") orelse Config.singlethreaded,
        .runtime_safety = b.option(bool, "runtime_safety", "Specify if engine should come with runtime data safety checks") orelse Config.runtime_safety,
        .ztracy_enable = b.option(bool, "ztracy", "Specify if program should come with ztracy benchmark tool") orelse Config.ztracy_enable,
        .c_bindings = b.option(bool, "Use_c_bindings", "Specify if program should come with c bindings(affects lua)") orelse Config.c_bindings,
        .use_lua = b.option(bool, "use_lua", "Specify if engine should support lua") orelse Config.use_lua,
        .zgui_shared = b.option(bool, "zgui_shared", "Specify if zgui should be built as shared library") orelse Config.Dependencies.zgui.shared,
        .build_vulkan = b.option(bool, "build_vulkan", "Specify if vulkan renderer should be included") orelse Config.build_vulkan,
        .build_opengl = b.option(bool, "build_opengl", "Specify if opengl renderer should be included") orelse Config.build_opengl,
        .build_directx = b.option(bool, "build_directx", "Specify if directx renderer should be included") orelse Config.build_directx,
        .renderer = b.option(Config.renderer_enum, "renderer", "Force some renderer to be used") orelse Config.renderer,
    };
}

const ExecutableConfig = struct {
    name: []const u8,
    user_module: ?*std.Build.Module = null,

    target: ?std.Build.ResolvedTarget = null,
    optimize: ?std.builtin.OptimizeMode = null,
};

pub fn build(b: *std.Build) !void {
    options = resolveOptions(b);
    const editor = b.step("editor", "Engine comes with default CLI program for lua parsing and project management");
    const binaries = try addEditor(b);
    for (binaries) |bin| {
        const install = b.addInstallArtifact(bin, .{});
        editor.dependOn(&install.step);
    }
}
pub fn addExecutable(b: *std.Build, config: ExecutableConfig) ![]*std.Build.Step.Compile {
    Config.profile();
    if (options == null) options = resolveOptions(b);
    const opts = options.?;
    const options_step = b.addOptions();
    options_step.addOption(bool, "singlethreaded", opts.singlethreaded);
    options_step.addOption(bool, "runtime_safety", opts.runtime_safety);
    options_step.addOption(bool, "has_user", if (config.user_module) |_| true else false);
    options_step.addOption(Config.renderer_enum, "renderer", opts.renderer);
    // Arguments passed to this build are composed to a module
    // which can be accessed later with just @import
    const BuildOptions = options_step.createModule();

    // Dependencies
    const ztracy = b.dependency("ztracy", .{
        .target = opts.target,
        .optimize = opts.optimize,
        .enable_ztracy = opts.ztracy_enable,
    });
    const ztracy_mod = ztracy.module("root");
    const luajit = b.dependency("zig_luajit", .{
        .target = opts.target,
        .optimize = opts.optimize,
    }).module("luajit");
    const glfw_dep = b.dependency("zglfw", .{
        .target = opts.target,
        .optimize = opts.optimize,
        .import_vulkan = if (opts.build_vulkan) true else false,
    });
    const glfw = glfw_dep.module("root");
    const vulkan_zig = b.dependency("vulkan_zig", .{
        .registry = b.dependency("vulkan_headers", .{}).path("registry/vk.xml"),
    }).module("vulkan-zig");
    const zgui_dep = b.dependency("zgui", .{
        .target = opts.target,
        .optimize = opts.optimize,
        .shared = false,
        .backend = .no_backend,
    });

    // Memory usage tracking
    const TrackingAllocator = b.addModule(
        "TrackingAllocator",
        .{
            .root_source_file = b.path("src/TrackingAllocator.zig"),
            .target = config.target orelse opts.target,
            .optimize = config.optimize orelse opts.optimize,
        },
    );
    TrackingAllocator.addImport("ztracy", ztracy_mod);

    // Runtime configuration
    const Conf = b.addModule("Conf", .{
        .root_source_file = b.path("src/Conf.zig"),
        .target = config.target orelse opts.target,
        .optimize = config.optimize orelse opts.optimize,
    });
    if (config.user_module) |user_module| user_module.addImport("Conf", Conf);
    Conf.addImport("BuildOptions", BuildOptions);

    // Input/Ouput system
    const IO = b.addModule(
        "IO",
        .{
            .root_source_file = b.path("src/IO/main.zig"),
            .target = config.target orelse opts.target,
            .optimize = config.optimize orelse opts.optimize,
        },
    );
    IO.addImport("TrackingAllocator", TrackingAllocator);

    // Async(multithreadong)
    const Async = b.addModule(
        "Async",
        .{
            .root_source_file = b.path("src/Async/main.zig"),
            .target = config.target orelse opts.target,
            .optimize = config.optimize orelse opts.optimize,
        },
    );
    Async.addImport("Conf", Conf);
    Async.addImport("TrackingAllocator", TrackingAllocator);
    Async.addImport("IO", IO);

    const C_API = if (opts.c_bindings) b.addModule("C_API", .{
        .target = opts.target,
        .optimize = opts.optimize,
        .link_libc = true,
        .root_source_file = b.path("bindings/C/main.zig"),
        .imports = &.{
            .{ .name = "IO", .module = IO },
            .{ .name = "Async", .module = Async },
            .{ .name = "TrackingAllocator", .module = TrackingAllocator },
            .{ .name = "Conf", .module = Conf },
        },
    }) else null;
    const Interface = b.addModule("GUI_interface", .{
        .root_source_file = b.path("src/GUI/interface.zig"),
        .target = opts.target,
        .optimize = opts.optimize,
        .imports = &.{
            .{ .name = "Async", .module = Async },
        },
    });

    const vulkan = if (opts.build_vulkan and (opts.renderer == .vulkan or opts.renderer == .automatic)) blk: {
        const mod = b.addModule("Vulkan_backend", .{
            .root_source_file = b.path("src/GUI/vulkan/main.zig"),
            .target = opts.target,
            .optimize = opts.optimize,
            .imports = &.{
                .{ .name = "Interface", .module = Interface },
                .{ .name = "TrackingAllocator", .module = TrackingAllocator },
                .{ .name = "glfw", .module = glfw },
                .{ .name = "vulkan", .module = vulkan_zig },
                .{ .name = "zgui_backend", .module = b.createModule(.{
                    .root_source_file = zgui_dep.path("src/backend_glfw_vulkan.zig"),
                    .target = opts.target,
                    .optimize = opts.optimize,
                }) },
                .{ .name = "Async", .module = Async },
                .{ .name = "Conf", .module = Conf },
            },
        });
        if (opts.target.result.os.tag != .emscripten) mod.linkLibrary(glfw_dep.artifact("glfw"));
        mod.linkLibrary(zgui_dep.artifact("imgui"));
        const lib = b.addLibrary(.{
            .name = "vulkan",
            .linkage = .dynamic,
            .root_module = mod,
        });
        break :blk lib;
    } else null;

    const GUI = b.addModule("GUI", .{
        .root_source_file = b.path("src/GUI/main.zig"),
        .target = opts.target,
        .optimize = opts.optimize,
        .imports = &.{
            .{ .name = "Interface", .module = Interface },
            .{ .name = "Conf", .module = Conf },
            .{ .name = "glfw", .module = glfw },
            .{ .name = "Async", .module = Async },
        },
    });

    const Lua = if (opts.use_lua) b.addModule("Lua", .{
        .target = opts.target,
        .optimize = opts.optimize,
        .link_libc = true,
        .root_source_file = b.path("bindings/Lua/main.zig"),
        .imports = &.{
            .{ .name = "LuaJIT", .module = luajit },
            .{ .name = "IO", .module = IO },
            .{ .name = "Async", .module = Async },
            .{ .name = "Conf", .module = Conf },
            .{ .name = "TrackingAllocator", .module = TrackingAllocator },
        },
    }) else null;
    // Engine struct
    const Engine = b.addModule("Engine", .{
        .root_source_file = b.path("src/root.zig"),
        .target = config.target orelse opts.target,
        .optimize = config.optimize orelse opts.optimize,
        .imports = &.{
            .{ .name = "IO", .module = IO },
            .{ .name = "Conf", .module = Conf },
            .{ .name = "TrackingAllocator", .module = TrackingAllocator },
            .{ .name = "Async", .module = Async },
            .{ .name = "ztracy", .module = ztracy_mod },
            .{ .name = "GUI", .module = GUI },
        },
    });
    if (config.user_module) |user_module| user_module.addImport("Engine", Engine);
    if (C_API) |_| Engine.addIncludePath(b.path("bindings/C"));
    if (Lua) |L| Engine.addImport("Lua", L);

    // Entrypoint of a final executable
    const Executable = b.addExecutable(.{
        .name = config.name,
        .root_module = b.createModule(.{
            .target = config.target orelse opts.target,
            .optimize = config.optimize orelse opts.optimize,
            .imports = &.{
                .{ .name = "Conf", .module = Conf },
                .{ .name = "Engine", .module = Engine },
                .{ .name = "IO", .module = IO },
                .{ .name = "TrackingAllocator", .module = TrackingAllocator },
            },
            .root_source_file = b.path("src/main.zig"),
        }),
    });
    if (config.user_module) |user_module| Executable.root_module.addImport("User", user_module);
    Executable.root_module.linkLibrary(ztracy.artifact("tracy"));
    if (C_API) |C| {
        Executable.root_module.addImport("C_API", C);
        Executable.root_module.addIncludePath(b.path("bindings/C"));
        if (config.user_module) |user_module| user_module.addIncludePath(b.path("bindings/C"));
    }
    var i: usize = 1;
    if (vulkan) |_| i += 1;
    const slice = try b.allocator.alloc(*std.Build.Step.Compile, i);
    i = 0;
    slice[i] = Executable;
    i += 1;
    if (vulkan) |vk| slice[i] = vk;

    return slice;
}

pub fn addEditor(b: *std.Build) ![]*std.Build.Step.Compile {
    const opts = options.?;
    const main = b.addModule("Editor", .{
        .root_source_file = b.path("src/Editor/main.zig"),
        .target = opts.target,
        .optimize = opts.optimize,
    });
    const binaries = try addExecutable(b, .{
        .name = "HEAT",
        .user_module = main,
    });
    return binaries;
}
