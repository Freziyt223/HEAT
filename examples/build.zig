const std = @import("std");

const Example = struct {
    name: []const u8,
    build_fn: *const fn (*std.Build, std.Build.ResolvedTarget, std.builtin.OptimizeMode) anyerror![]*std.Build.Step.Compile,
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
    const optimize = b.standardOptimizeOption(.{ .preferred_optimize_mode = .ReleaseFast });

    for (examples[0..]) |ex| {
        const binaries = try ex.build_fn(b, target, optimize);
        // 1. Create a step to build/install this specific example: `zig build <name>`
        const build_step = b.step(ex.name, b.fmt("Build the '{s}' example", .{ex.name}));
        for (binaries) |bin| {
            const install = b.addInstallArtifact(bin, .{});
            build_step.dependOn(&install.step);
            b.getInstallStep().dependOn(&install.step);
        }

        // 3. Create a step to run this specific example: `zig build run-<name>`
        const run_cmd = b.addRunArtifact(binaries[0]);
        if (b.args) |args| {
            run_cmd.addArgs(args);
        }
        // All libraries must be built for run step to proceed
        run_cmd.step.dependOn(build_step);

        const run_step = b.step(b.fmt("run-{s}", .{ex.name}), b.fmt("Run the '{s}' example", .{ex.name}));
        run_step.dependOn(&run_cmd.step);
    }
}
