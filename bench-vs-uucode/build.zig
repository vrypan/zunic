const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const zunic = b.dependency("zunic", .{ .target = target, .optimize = optimize });
    const uucode = b.dependency("uucode", .{
        .target = target,
        .optimize = optimize,
        // Configure only the data used by the comparable operations.
        .fields = @as([]const []const u8, &.{
            "grapheme_break",
            "is_emoji_vs_base",
            "wcwidth_standalone",
            "wcwidth_zero_in_grapheme",
        }),
    });

    const generated = b.addWriteFiles();
    const benchmark_source = generated.addCopyFile(b.path("src/benchmark.zig"), "benchmark.zig");
    _ = generated.addCopyDirectory(b.path("../bench-vs-rust/texts"), "texts", .{});

    const Peer = struct {
        name: []const u8,
        source: []const u8,
        import_name: []const u8,
        import_module: *std.Build.Module,
    };
    const peers = [_]Peer{
        .{ .name = "zunic-bench", .source = "src/zunic.zig", .import_name = "zunic", .import_module = zunic.module("zunic") },
        .{ .name = "uucode-bench", .source = "src/uucode.zig", .import_name = "uucode", .import_module = uucode.module("uucode") },
    };

    const test_step = b.step("test", "Run both peer adapters against the shared harness");
    for (peers) |peer| {
        const adapter = b.createModule(.{ .root_source_file = b.path(peer.source), .target = target, .optimize = optimize });
        adapter.addImport(peer.import_name, peer.import_module);

        const module = b.createModule(.{ .root_source_file = benchmark_source, .target = target, .optimize = optimize });
        module.addImport("peer", adapter);
        const executable = b.addExecutable(.{ .name = peer.name, .root_module = module });
        b.installArtifact(executable);

        const tests = b.addTest(.{ .root_module = module });
        test_step.dependOn(&b.addRunArtifact(tests).step);
    }
}
