const std = @import("std");

const Example = struct {
    name: []const u8,
    build_fn: *const fn (*std.Build, std.Build.ResolvedTarget, std.builtin.OptimizeMode, bool, bool) anyerror![]*std.Build.Step.Compile,
};

const examples = [_]Example{
    .{
        .name = "basic",
        .build_fn = @import("basic/build_example.zig").build,
    },
    .{
        .name = "C",
        .build_fn = @import("C/build_example.zig").build,
    },
    .{
        .name = "basic-window",
        .build_fn = @import("basic-window/build_example.zig").build,
    },
};

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.option(std.builtin.OptimizeMode, "Optimize", "Specify optimize mode") orelse .Debug;
    const multitarget = b.option(bool, "multitarget", "Build examples for Config.targets") orelse true;
    const use_lua = b.option(bool, "use_lua", "Build Lua support where the target can run LuaJIT build tools") orelse true;

    for (examples[0..]) |ex| {
        const binaries = try ex.build_fn(b, target, optimize, multitarget, use_lua);
        if (binaries.len == 0) continue;
        // 1. Create a step to build/install this specific example: `zig build <name>`
        const build_step = b.step(ex.name, b.fmt("Build the '{s}' example", .{ex.name}));
        for (binaries) |bin| {
            const target_info = bin.root_module.resolved_target.?.result;
            const path = b.fmt("{s}/{s}", .{ @tagName(target_info.os.tag), @tagName(target_info.cpu.arch) });
            const install = b.addInstallArtifact(bin, .{ .dest_dir = .{ .override = .{ .custom = path } } });
            build_step.dependOn(&install.step);
            b.getInstallStep().dependOn(&install.step);
        }

        // 3. Create a step to run this specific example: `zig build run-<name>`
        var run_binary = binaries[0];
        for (binaries) |bin| {
            const bin_target = bin.root_module.resolved_target.?.result;
            if (bin_target.os.tag == target.result.os.tag and bin_target.cpu.arch == target.result.cpu.arch) {
                run_binary = bin;
                break;
            }
        }
        const run_cmd = b.addRunArtifact(run_binary);
        if (b.args) |args| {
            run_cmd.addArgs(args);
        }
        // All libraries must be built for run step to proceed
        run_cmd.step.dependOn(build_step);

        const run_step = b.step(b.fmt("run-{s}", .{ex.name}), b.fmt("Run the '{s}' example", .{ex.name}));
        run_step.dependOn(&run_cmd.step);
    }
}
