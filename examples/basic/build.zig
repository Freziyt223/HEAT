const std = @import("std");

pub fn build(b: *std.Build) void {
    const Example = b.addModule("Example", .{
        .root_source_file = b.path("main.zig"),
    });

    const Exe = @import("HEAT").addExecutable(b, .{
        .name = "basic",
        .user_module = Example
    });
    
    b.installArtifact(Exe);
}
