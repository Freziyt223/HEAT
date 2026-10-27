//! HEAT build configuration and reusable package build helpers.
const std = @import("std");
pub const Config = @import("config.zig");

const Module = *std.Build.Module;

const Options = struct {
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    singlethreaded: bool,
    runtime_safety: bool,
    ztracy: bool,
    multitarget: bool,
    c_bindings: bool,
    lua: bool,
    glfw: bool,
    gui: bool,
    zgui_shared: bool,
    vulkan: bool,
    opengl: bool,
    directx: bool,
    renderer: Config.renderer_enum,
};

const ExecutableConfig = struct {
    name: []const u8,
    user_module: ?Module = null,
    target: ?std.Build.ResolvedTarget = null,
    optimize: ?std.builtin.OptimizeMode = null,
};

const CoreModules = struct {
    tracking_allocator: Module,
    conf: Module,
    io: Module,
    async: Module,
    module_helpers: Module,
};

const BindingModules = struct {
    c_api: ?Module,
    lua: ?Module,
};

// Build options belong to the Build instance. Keep one resolved snapshot because
// consumers may call addExecutable several times while declaring examples.
var cached_options: ?Options = null;

fn resolveOptions(b: *std.Build) Options {
    return .{
        .target = b.standardTargetOptions(.{}),
        .optimize = b.option(std.builtin.OptimizeMode, "Optimize", "Optimization mode for HEAT") orelse Config.optimize,
        .singlethreaded = b.option(bool, "singlethreaded", "Build the engine without worker threads") orelse Config.singlethreaded,
        .runtime_safety = b.option(bool, "runtime_safety", "Enable runtime safety checks") orelse Config.runtime_safety,
        .ztracy = b.option(bool, "ztracy", "Enable Tracy profiling") orelse Config.ztracy_enable,
        .multitarget = b.option(bool, "multitarget", "Build for every target in Config.targets") orelse Config.multitarget,
        .c_bindings = b.option(bool, "c_bindings", "Build the C API") orelse
            b.option(bool, "Use_c_bindings", "Legacy option; prefer -Dc_bindings") orelse Config.c_bindings,
        .lua = b.option(bool, "use_lua", "Build Lua support") orelse Config.use_lua,
        .glfw = b.option(bool, "use_glfw", "Build GLFW windowing support") orelse Config.use_glfw,
        .gui = b.option(bool, "gui", "Build the GUI and rendering modules") orelse Config.gui,
        .zgui_shared = b.option(bool, "zgui_shared", "Build zgui as a shared library") orelse Config.Dependencies.zgui.shared,
        .vulkan = b.option(bool, "build_vulkan", "Enable the Vulkan renderer") orelse Config.build_vulkan,
        .opengl = b.option(bool, "build_opengl", "Enable the OpenGL renderer") orelse Config.build_opengl,
        .directx = b.option(bool, "build_directx", "Enable the DirectX renderer") orelse Config.build_directx,
        .renderer = b.option(Config.renderer_enum, "renderer", "Select the renderer") orelse Config.renderer,
    };
}

fn getOptions(b: *std.Build) Options {
    if (cached_options == null) cached_options = resolveOptions(b);
    return cached_options.?;
}

fn addBuildOptions(b: *std.Build, options: Options, has_user: bool) Module {
    const generated = b.addOptions();
    generated.addOption(bool, "singlethreaded", options.singlethreaded);
    generated.addOption(bool, "runtime_safety", options.runtime_safety);
    generated.addOption(bool, "gui", options.gui);
    generated.addOption(bool, "lua", options.lua);
    generated.addOption(bool, "has_user", has_user);
    generated.addOption(Config.renderer_enum, "renderer", options.renderer);
    return generated.createModule();
}

fn addCoreModules(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    build_options: Module,
    user_module: ?Module,
    ztracy: Module,
) CoreModules {
    const tracking_allocator = b.addModule("TrackingAllocator", .{
        .root_source_file = b.path("src/TrackingAllocator.zig"),
        .target = target,
        .optimize = optimize,
    });
    tracking_allocator.addImport("ztracy", ztracy);

    const module_helpers = b.addModule("Module", .{
        .root_source_file = b.path("src/Module.zig"),
        .target = target,
        .optimize = optimize,
    });

    const conf = b.addModule("Conf", .{
        .root_source_file = b.path("src/Conf.zig"),
        .target = target,
        .optimize = optimize,
    });
    conf.addImport("BuildOptions", build_options);
    if (user_module) |user| user.addImport("Conf", conf);

    const io = b.addModule("IO", .{
        .root_source_file = b.path("src/IO/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    io.addImport("TrackingAllocator", tracking_allocator);

    const async = b.addModule("Async", .{
        .root_source_file = b.path("src/Async/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    async.addImport("Conf", conf);
    async.addImport("TrackingAllocator", tracking_allocator);
    async.addImport("IO", io);

    return .{
        .tracking_allocator = tracking_allocator,
        .conf = conf,
        .io = io,
        .async = async,
        .module_helpers = module_helpers,
    };
}

fn addGuiModule(
    b: *std.Build,
    options: Options,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    core: CoreModules,
) Module {
    if (!options.gui) {
        return b.addModule("GUI", .{
            .root_source_file = b.path("src/GUI/default.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "Async", .module = core.async },
                .{ .name = "TrackingAllocator", .module = core.tracking_allocator },
            },
        });
    }

    const gui = b.addModule("GUI", .{
        .root_source_file = b.path("src/GUI/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "TrackingAllocator", .module = core.tracking_allocator },
            .{ .name = "Conf", .module = core.conf },
            .{ .name = "Async", .module = core.async },
        },
    });
    if (!options.glfw) return gui;

    const interface = b.addModule("GUI_Interface", .{
        .root_source_file = b.path("src/GUI/interface.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "Async", .module = core.async }},
    });

    const glfw_dependency = b.dependency("zglfw", .{
        .target = target,
        .optimize = optimize,
        .import_vulkan = options.vulkan,
    });
    const glfw = glfw_dependency.module("root");
    interface.addImport("zglfw", glfw);
    gui.addImport("zglfw", glfw);
    gui.addImport("Interface", interface);
    if (target.result.os.tag != .emscripten) {
        gui.linkLibrary(glfw_dependency.artifact("glfw"));
    }

    const zgui_dependency = b.dependency("zgui", .{
        .target = target,
        .optimize = optimize,
        .shared = options.zgui_shared,
        .backend = .glfw_vulkan,
    });
    const zgui = zgui_dependency.module("root");
    gui.addImport("zgui", zgui);
    const imgui = zgui_dependency.artifact("imgui");
    imgui.root_module.addCMacro("GLFW_INCLUDE_NONE", "1");
    gui.linkLibrary(imgui);

    if (options.renderer == .bgfx or options.renderer == .automatic) {
        const bgfx_dependency = b.dependency("zbgfx", .{
            .target = target,
            .optimize = optimize,
        });
        const bgfx = b.createModule(.{
            .root_source_file = b.path("src/GUI/bgfx/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "Async", .module = core.async },
                .{ .name = "TrackingAllocator", .module = core.tracking_allocator },
                .{ .name = "Interface", .module = interface },
                .{ .name = "zglfw", .module = glfw },
                .{ .name = "zgui", .module = zgui },
                .{ .name = "zbgfx", .module = bgfx_dependency.module("root") },
            },
        });
        bgfx.linkLibrary(bgfx_dependency.artifact("bgfx"));
        gui.addImport("bgfx", bgfx);
    } else if (options.vulkan and options.renderer == .vulkan) {
        const vulkan_headers = b.dependency("vulkan_headers", .{});
        const vulkan = b.dependency("vulkan_zig", .{
            .registry = vulkan_headers.path("registry/vk.xml"),
        }).module("vulkan-zig");
        const renderer = b.createModule(.{
            .root_source_file = b.path("src/GUI/vulkan/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "TrackingAllocator", .module = core.tracking_allocator },
                .{ .name = "Conf", .module = core.conf },
                .{ .name = "IO", .module = core.io },
                .{ .name = "Async", .module = core.async },
                .{ .name = "vulkan", .module = vulkan },
                .{ .name = "glfw", .module = glfw },
                .{ .name = "Interface", .module = interface },
                .{ .name = "zgui", .module = zgui },
            },
        });
        gui.addImport("vulkan", renderer);
        glfw.addImport("vulkan", vulkan);
    }

    return gui;
}

fn addBindingModules(
    b: *std.Build,
    options: Options,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    core: CoreModules,
    luajit: ?Module,
) BindingModules {
    const c_api = if (options.c_bindings) b.addModule("C_API", .{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .root_source_file = b.path("bindings/C/main.zig"),
        .imports = &.{
            .{ .name = "IO", .module = core.io },
            .{ .name = "Async", .module = core.async },
            .{ .name = "TrackingAllocator", .module = core.tracking_allocator },
            .{ .name = "Conf", .module = core.conf },
        },
    }) else null;

    const lua = if (options.lua) b.addModule("Lua", .{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .root_source_file = b.path("bindings/Lua/main.zig"),
        .imports = &.{
            .{ .name = "LuaJIT", .module = luajit.? },
            .{ .name = "IO", .module = core.io },
            .{ .name = "Async", .module = core.async },
            .{ .name = "Conf", .module = core.conf },
            .{ .name = "TrackingAllocator", .module = core.tracking_allocator },
        },
    }) else null;

    return .{ .c_api = c_api, .lua = lua };
}

fn addEngineModule(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    core: CoreModules,
    gui: Module,
    ztracy: Module,
    bindings: BindingModules,
    user_module: ?Module,
) Module {
    const engine = b.addModule("Engine", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "IO", .module = core.io },
            .{ .name = "Conf", .module = core.conf },
            .{ .name = "TrackingAllocator", .module = core.tracking_allocator },
            .{ .name = "Async", .module = core.async },
            .{ .name = "ztracy", .module = ztracy },
            .{ .name = "GUI", .module = gui },
            .{ .name = "Module", .module = core.module_helpers },
        },
    });

    if (user_module) |user| user.addImport("Engine", engine);
    if (bindings.c_api != null) engine.addIncludePath(b.path("bindings/C"));
    if (bindings.lua) |lua| engine.addImport("Lua", lua);
    return engine;
}

fn addExecutableRoot(
    b: *std.Build,
    name: []const u8,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    core: CoreModules,
    engine: Module,
    user_module: ?Module,
    c_api: ?Module,
    tracy_library: *std.Build.Step.Compile,
) *std.Build.Step.Compile {
    const exe = b.addExecutable(.{
        .name = name,
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "Conf", .module = core.conf },
                .{ .name = "Engine", .module = engine },
                .{ .name = "IO", .module = core.io },
                .{ .name = "TrackingAllocator", .module = core.tracking_allocator },
            },
        }),
    });

    if (user_module) |user| exe.root_module.addImport("User", user);
    exe.root_module.linkLibrary(tracy_library);
    if (target.result.os.tag == .linux) {
        const system_sdk = b.dependency("system_sdk", .{});
        const library_dir = if (target.result.cpu.arch.isX86())
            "linux/lib/x86_64-linux-gnu"
        else
            "linux/lib/aarch64-linux-gnu";
        exe.root_module.addLibraryPath(system_sdk.path(library_dir));
    }
    if (c_api) |c| {
        exe.root_module.addImport("C_API", c);
        exe.root_module.addIncludePath(b.path("bindings/C"));
        if (user_module) |user| user.addIncludePath(b.path("bindings/C"));
    }
    return exe;
}

fn addExecutableWithOptions(
    b: *std.Build,
    config: ExecutableConfig,
    options: Options,
) ![]*std.Build.Step.Compile {
    Config.profile();
    const target = config.target orelse options.target;
    const optimize = config.optimize orelse options.optimize;
    var target_options = options;
    target_options.target = target;
    target_options.optimize = optimize;
    if (target_options.lua and !supportsLuaBuildTarget(b, target)) {
        std.log.warn("LuaJIT is disabled for cross target {s}; build it on a matching host to include Lua", .{@tagName(target.result.os.tag)});
        target_options.lua = false;
    }
    const build_options = addBuildOptions(b, target_options, config.user_module != null);

    const tracy_dependency = b.dependency("ztracy", .{
        .target = target,
        .optimize = optimize,
        .enable_ztracy = target_options.ztracy,
    });
    const tracy = tracy_dependency.module("root");
    const luajit = if (target_options.lua) b.dependency("zig_luajit", .{
        .target = target,
        .optimize = optimize,
    }).module("luajit") else null;

    const core = addCoreModules(b, target, optimize, build_options, config.user_module, tracy);
    const gui = addGuiModule(b, target_options, target, optimize, core);
    const bindings = addBindingModules(b, target_options, target, optimize, core, luajit);
    const engine = addEngineModule(b, target, optimize, core, gui, tracy, bindings, config.user_module);
    const exe = addExecutableRoot(
        b,
        config.name,
        target,
        optimize,
        core,
        engine,
        config.user_module,
        bindings.c_api,
        tracy_dependency.artifact("tracy"),
    );

    const result = try b.allocator.alloc(*std.Build.Step.Compile, 1);
    result[0] = exe;
    return result;
}

fn supportsLuaBuildTarget(b: *const std.Build, target: std.Build.ResolvedTarget) bool {
    const host = b.graph.host.result;
    return target.result.os.tag == host.os.tag and
        target.result.cpu.arch == host.cpu.arch and
        target.result.abi == host.abi;
}

pub fn addExecutable(b: *std.Build, config: ExecutableConfig) ![]*std.Build.Step.Compile {
    const options = getOptions(b);
    if (!options.multitarget or config.target != null or config.user_module != null) return addExecutableWithOptions(b, config, options);

    var executables: std.ArrayList(*std.Build.Step.Compile) = .empty;
    for (Config.targets.items) |query| {
        var target_options = options;
        target_options.target = b.resolveTargetQuery(query);
        const target_executables = try addExecutableWithOptions(b, config, target_options);
        try executables.appendSlice(b.allocator, target_executables);
    }
    return executables.toOwnedSlice(b.allocator);
}

fn addEditor(b: *std.Build, options: Options) ![]*std.Build.Step.Compile {
    if (!options.multitarget) {
        const editor = b.addModule("Editor", .{
            .root_source_file = b.path("src/Editor/main.zig"),
            .target = options.target,
            .optimize = options.optimize,
        });
        return addExecutableWithOptions(b, .{ .name = "HEAT", .user_module = editor }, options);
    }
    var executables: std.ArrayList(*std.Build.Step.Compile) = .empty;
    for (Config.targets.items) |query| {
        var target_options = options;
        target_options.target = b.resolveTargetQuery(query);
        const editor = b.addModule("Editor", .{
            .root_source_file = b.path("src/Editor/main.zig"),
            .target = target_options.target,
            .optimize = options.optimize,
        });
        const built = try addExecutableWithOptions(b, .{ .name = "HEAT", .user_module = editor }, target_options);
        try executables.appendSlice(b.allocator, built);
    }
    return executables.toOwnedSlice(b.allocator);
}

pub fn build(b: *std.Build) !void {
    const options = getOptions(b);
    const editor_step = b.step("editor", "Build the HEAT editor executable");
    const executables = try addEditor(b, options);
    for (executables) |exe| {
        const target = exe.root_module.resolved_target.?.result;
        const path = b.fmt("{s}/{s}", .{ @tagName(target.os.tag), @tagName(target.cpu.arch) });
        const install = b.addInstallArtifact(exe, .{ .dest_dir = .{ .override = .{ .custom = path } } });
        editor_step.dependOn(&install.step);
    }
    b.default_step.dependOn(editor_step);
}
