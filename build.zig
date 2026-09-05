const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const zunic = b.addModule("zunic", .{
        .root_source_file = b.path("src/root.zig"),
    });
    const test_step = b.step("test", "Run zunic tests");
    const roots = [_][]const u8{
        "src/root_test.zig",
        "src/conformance_test.zig",
    };
    for (roots) |root| {
        const test_mod = b.createModule(.{
            .root_source_file = b.path(root),
            .target = target,
            .optimize = optimize,
        });
        test_mod.addImport("zunic", zunic);
        test_step.dependOn(&b.addRunArtifact(b.addTest(.{ .root_module = test_mod })).step);
    }
}
