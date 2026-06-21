const std = @import("std");
// Pass the name you've used in build.zig.zon's dependencies
const HEAT = @import("HEAT");

/// *Compile used here to return to examples' build.zig, in your case it will be !void
pub fn build(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) !*std.Build.Step.Compile {
    // You have to use HEAT's builder for `addExecutable` function
    const HEAT_dep = b.dependency("HEAT", .{
        .target = target,
        .optimize = optimize,
    });
    _ = HEAT.addEditor(HEAT_dep.builder);
}
