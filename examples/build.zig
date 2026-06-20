const std = @import("std");

const Example = struct {
    name: []const u8,
    build_fn: *const fn (*std.Build, std.Build.ResolvedTarget, std.builtin.OptimizeMode) anyerror!*std.Build.Step.Compile,
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
};

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{ .preferred_optimize_mode = .ReleaseFast });

    for (examples[0..]) |ex| {
        const exe = try ex.build_fn(b, target, optimize);

        // 1. Create a step to build/install this specific example: `zig build <name>`
        const install_artifact = b.addInstallArtifact(exe, .{});
        const build_step = b.step(ex.name, b.fmt("Build the '{s}' example", .{ex.name}));
        build_step.dependOn(&install_artifact.step);

        // 2. Create a step to run this specific example: `zig build run-<name>`
        const run_cmd = b.addRunArtifact(exe);
        if (b.args) |args| {
            run_cmd.addArgs(args);
        }
        const run_step = b.step(b.fmt("run-{s}", .{ex.name}), b.fmt("Run the '{s}' example", .{ex.name}));
        run_step.dependOn(&run_cmd.step);

        // By default, `zig build` builds and installs all examples
        b.getInstallStep().dependOn(&install_artifact.step);
    }
}
