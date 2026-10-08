//! Use addExecutable to install your code with engine's
//! To run examples run zig build inside examples folder
const std = @import("std");
pub const Config = @import("config.zig");

const ResolvedOptions = struct {
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    singlethreaded: bool,
    runtime_safety: bool,
    ztracy_enable: bool,
    c_bindings: bool,
    use_lua: bool,
    use_glfw: bool,
    gui: bool,
    zgui_shared: bool,
    build_vulkan: bool,
    build_opengl: bool,
    build_directx: bool,
    renderer: Config.renderer_enum,
};

var options: ?ResolvedOptions = null;

fn resolveOptions(b: *std.Build) ResolvedOptions {
    return .{
        .target = b.standardTargetOptions(.{}),
        .optimize = b.option(std.builtin.OptimizeMode, "Optimize", "Select mode which will be used to compile an executable") orelse Config.optimize,
        .singlethreaded = b.option(bool, "singlethreaded", "Specify if engine should be compiled as singlethreaded") orelse Config.singlethreaded,
        .runtime_safety = b.option(bool, "runtime_safety", "Specify if engine should come with runtime data safety checks") orelse Config.runtime_safety,
        .ztracy_enable = b.option(bool, "ztracy", "Specify if program should come with ztracy benchmark tool") orelse Config.ztracy_enable,
        .c_bindings = b.option(bool, "Use_c_bindings", "Specify if program should come with c bindings(affects lua)") orelse Config.c_bindings,
        .use_lua = b.option(bool, "use_lua", "Specify if engine should support lua") orelse Config.use_lua,
        .use_glfw = b.option(bool, "use_glfw", "Specify if engine should use glfw") orelse Config.use_glfw,
        .gui = b.option(bool, "gui", "Specify if engine should come with any GUI and rendering code") orelse Config.gui,
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

pub fn addExecutable(b: *std.Build, config: ExecutableConfig) ![]*std.Build.Step.Compile {
    Config.profile();
    if (options == null) options = resolveOptions(b);
    const opts = options.?;

    const target = config.target orelse opts.target;
    const optimize = config.optimize orelse opts.optimize;

    // --- Build Options ---
    const options_step = b.addOptions();
    options_step.addOption(bool, "singlethreaded", opts.singlethreaded);
    options_step.addOption(bool, "runtime_safety", opts.runtime_safety);
    options_step.addOption(bool, "gui", opts.gui);
    options_step.addOption(bool, "has_user", if (config.user_module) |_| true else false);
    options_step.addOption(Config.renderer_enum, "renderer", opts.renderer);
    const BuildOptions = options_step.createModule();

    // ===============================
    // --- Base Dependencies ---
    // ===============================

    const ztracy = b.dependency("ztracy", .{
        .target = target,
        .optimize = optimize,
        .enable_ztracy = opts.ztracy_enable,
    });
    const ztracy_mod = ztracy.module("root");

    const luajit = b.dependency("zig_luajit", .{
        .target = target,
        .optimize = optimize,
    }).module("luajit");

    // ===========================
    // --- Core Submodules ---
    // ===========================

    const TrackingAllocator = b.addModule("TrackingAllocator", .{
        .root_source_file = b.path("src/TrackingAllocator.zig"),
        .target = target,
        .optimize = optimize,
    });
    TrackingAllocator.addImport("ztracy", ztracy_mod);

    const Conf = b.addModule("Conf", .{
        .root_source_file = b.path("src/Conf.zig"),
        .target = target,
        .optimize = optimize,
    });
    if (config.user_module) |user_module| user_module.addImport("Conf", Conf);
    Conf.addImport("BuildOptions", BuildOptions);

    const IO = b.addModule("IO", .{
        .root_source_file = b.path("src/IO/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    IO.addImport("TrackingAllocator", TrackingAllocator);

    const Async = b.addModule("Async", .{
        .root_source_file = b.path("src/Async/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    Async.addImport("Conf", Conf);
    Async.addImport("TrackingAllocator", TrackingAllocator);
    Async.addImport("IO", IO);
    const GUI = blk: {
        if (opts.gui) {
            const impl = b.addModule("GUI", .{
                .root_source_file = if (opts.gui) b.path("src/GUI/main.zig") else b.path("src/GUI/stub.zig"),
                .target = target,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = "TrackingAllocator", .module = TrackingAllocator },
                    .{ .name = "Conf", .module = Conf },
                    .{ .name = "Async", .module = Async },
                },
            });
            // Windowing (GLFW)
            if (opts.use_glfw) {
                const Interface = b.addModule("GUI_Interface", .{
                    .root_source_file = b.path("src/GUI/interface.zig"),
                    .target = target,
                    .optimize = optimize,
                    .imports = &.{
                        .{ .name = "Async", .module = Async },
                    },
                });
                const zglfw_dep = b.dependency("zglfw", .{
                    .target = target,
                    .optimize = optimize,
                    .import_vulkan = opts.build_vulkan,
                });
                const zglfw = zglfw_dep.module("root");
                Interface.addImport("zglfw", zglfw);
                impl.addImport("zglfw", zglfw);
                impl.addImport("Interface", Interface);

                if (target.result.os.tag != .emscripten) {
                    impl.linkLibrary(zglfw_dep.artifact("glfw"));
                }

                // UI Layer (zgui)
                const zgui_dep = b.dependency("zgui", .{
                    .target = target,
                    .optimize = optimize,
                    .shared = opts.zgui_shared,
                    .backend = .glfw_vulkan,
                });
                const zgui = zgui_dep.module("root");
                impl.addImport("zgui", zgui);
                impl.linkLibrary(zgui_dep.artifact("imgui"));

                // Renderer Backend (zbgfx or Vulkan)
                if (opts.renderer == .bgfx or opts.renderer == .automatic) {
                    const zbgfx_dep = b.dependency("zbgfx", .{
                        .target = target,
                        .optimize = optimize,
                    });
                    const bgfx = b.createModule(.{
                        .root_source_file = b.path("src/GUI/bgfx/main.zig"),
                        .target = target,
                        .optimize = optimize,
                        .imports = &.{
                            .{ .name = "Async", .module = Async },
                            .{ .name = "TrackingAllocator", .module = TrackingAllocator },
                            .{ .name = "Interface", .module = Interface },
                            .{ .name = "zglfw", .module = zglfw },
                            .{ .name = "zgui", .module = zgui },
                            .{ .name = "zbgfx", .module = zbgfx_dep.module("root") },
                        },
                    });
                    bgfx.linkLibrary(zbgfx_dep.artifact("bgfx"));
                    impl.addImport("bgfx", bgfx);
                } else if (opts.build_vulkan and opts.renderer == .vulkan) {
                    const vulkan_zig = b.dependency("vulkan_zig", .{
                        .registry = b.dependency("vulkan_headers", .{}).path("registry/vk.xml"),
                        .target = target,
                        .optimize = optimize,
                    }).module("vulkan-zig");
                    const vulkan = b.createModule(.{
                        .root_source_file = b.path("src/GUI/vulkan/main.zig"),
                        .target = target,
                        .optimize = optimize,
                        .imports = &.{
                            .{ .name = "TrackingAllocator", .module = TrackingAllocator },
                            .{ .name = "Conf", .module = Conf },
                            .{ .name = "IO", .module = IO },
                            .{ .name = "Async", .module = Async },
                            .{ .name = "vulkan", .module = vulkan_zig },
                            .{ .name = "glfw", .module = zglfw },
                            .{ .name = "Interface", .module = Interface },
                            .{ .name = "zgui", .module = zgui },
                        },
                    });
                    impl.addImport("vulkan", vulkan);
                    zglfw.addImport("vulkan", vulkan_zig);
                }
            }
            break :blk impl;
        } else break :blk b.addModule("GUI", .{
            .root_source_file = b.path("src/GUI/stub.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "Async", .module = Async },
                .{ .name = "TrackingAllocator", .module = TrackingAllocator },
            },
        });
    };

    // ===========================
    // --- C Bindings & Lua ---
    // ===========================

    const C_API = if (opts.c_bindings) b.addModule("C_API", .{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .root_source_file = b.path("bindings/C/main.zig"),
        .imports = &.{
            .{ .name = "IO", .module = IO },
            .{ .name = "Async", .module = Async },
            .{ .name = "TrackingAllocator", .module = TrackingAllocator },
            .{ .name = "Conf", .module = Conf },
        },
    }) else null;

    const Lua = if (opts.use_lua) b.addModule("Lua", .{
        .target = target,
        .optimize = optimize,
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

    // --- Core Engine ---
    const Engine = b.addModule("Engine", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
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

    // --- Executable ---
    const Executable = b.addExecutable(.{
        .name = config.name,
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
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

    const slice = try b.allocator.alloc(*std.Build.Step.Compile, 1);
    slice[0] = Executable;
    return slice;
}

pub fn addEditor(b: *std.Build) ![]*std.Build.Step.Compile {
    const opts = options.?;
    const main = b.addModule("Editor", .{
        .root_source_file = b.path("src/Editor/main.zig"),
        .target = opts.target,
        .optimize = opts.optimize,
    });
    return try addExecutable(b, .{
        .name = "HEAT",
        .user_module = main,
    });
}

pub fn build(b: *std.Build) !void {
    options = resolveOptions(b);
    const editor = b.step("editor", "Engine comes with default CLI program for lua parsing and project management");
    const binaries = try addEditor(b);
    for (binaries) |bin| {
        const install = b.addInstallArtifact(bin, .{});
        editor.dependOn(&install.step);
    }
}
