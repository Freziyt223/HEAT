const std = @import("std");
// Pass the name you've used in build.zig.zon's dependencies
const HEAT = @import("HEAT");

/// *Compile used here to return to examples' build.zig, in your case it will be !void
pub fn build(b: *std.Build, default_target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode, multitarget: bool, use_lua: bool) ![]*std.Build.Step.Compile {
    // _ = optimize;
    // const mode = std.builtin.OptimizeMode.ReleaseFast;
    // HEAT.Config.optimize = mode;
    const mode = optimize;
    // You have to use HEAT's builder for `addExecutable` function
    const HEAT_dep = b.dependency("HEAT", .{});
    const builder = HEAT_dep.builder;
    HEAT.Config.multitarget = multitarget;
    HEAT.Config.use_lua = use_lua;

    var binaries: std.ArrayList(*std.Build.Step.Compile) = .empty;
    if (multitarget) {
        for (HEAT.Config.targets.items) |query| {
            const target = b.resolveTargetQuery(query);
            try binaries.appendSlice(b.allocator, try addTarget(b, builder, target, mode));
        }
    } else {
        try binaries.appendSlice(b.allocator, try addTarget(b, builder, default_target, mode));
    }
    return binaries.toOwnedSlice(b.allocator);
}

fn addTarget(b: *std.Build, builder: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) ![]*std.Build.Step.Compile {
    const example = b.createModule(.{
        .root_source_file = b.path("basic/src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    return HEAT.addExecutable(builder, .{ .name = "basic", .user_module = example, .target = target, .optimize = optimize });
}
