const std = @import("std");
const Config = @import("config.zig");

pub fn build(b: *std.Build) void {
    
}

const ResolvedOptions = struct {

};
pub fn resolveOptions(b: *std.Build) ResolvedOptions {

}

const ExecutableConfig = struct {
    name: []const u8,
    user_module: *std.Build.Module,

    target: ?std.Build.ResolvedTarget = null,
    optimize: ?std.builtin.OptimizeMode = null,
};
pub fn addExecutable(b: *std.Build, config: ExecutableConfig) *std.Build.Step.Compile {
    const options = resolveOptions(b);
    const Executable = b.addExecutable(.{
        .name = config.name,
        .root_module = b.createModule(.{
            .target = config.target orelse options.target,
            .optimize = config.optimize orelse options.target,
            .imports = &.{
                .{ .name = "user", .module = config.user_module}
            },
            .root_source_file = b.path("src/main.zig"),
        })
    });

    return Executable;
}