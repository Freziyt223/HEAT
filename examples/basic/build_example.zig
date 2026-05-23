const std = @import("std");
// Pass the name you've used in build.zig.zon's dependencies
const HEAT = @import("HEAT");

/// *Compile used here to return to examples' build.zig, in your case it will be !void
pub fn build(b: *std.Build) !*std.Build.Step.Compile {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{ .preferred_optimize_mode = .ReleaseFast });

    // You have to use HEAT's builder for `addExecutable` function
    const HEAT_dep = b.dependency("HEAT", .{});
    const builder = HEAT_dep.builder;

    const example = b.createModule(.{
        .root_source_file = b.path("basic/src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    // creation of a program Example
    const exe = HEAT.addExecutable(builder, .{
        .name = "basic",
        .user_module = example,
    });

    return exe;
}
