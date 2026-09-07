const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const WrapFastPath = enum { off, scalar, auto, simd };
    const wrap_fast_path = b.option(WrapFastPath, "wrap-fast-path", "ASCII fast-path backend for wrapping and width") orelse .auto;
    if (wrap_fast_path == .simd and switch (target.result.cpu.arch) {
        .aarch64, .x86_64 => false,
        else => true,
    }) @panic("-Dwrap-fast-path=simd requires an aarch64 or x86_64 target");
    // Working-buffer size for one normalization iterator, in bytes. Each entry
    // is a scalar plus its combining class packed into a u32, and two entries
    // are headroom, so 128 bytes admits a run of 30 non-starters. It is a
    // compile-time module setting, not a runtime allocation: see plan 023.
    const normalization_buffer_bytes = b.option(
        usize,
        "normalization-buffer-bytes",
        "Working buffer for one normalization iterator; a positive multiple of 32 (default 128)",
    ) orelse 128;
    if (normalization_buffer_bytes == 0 or normalization_buffer_bytes % 32 != 0)
        @panic("-Dnormalization-buffer-bytes must be a positive multiple of 32");
    const build_options = b.addOptions();
    build_options.addOption(WrapFastPath, "wrap_fast_path", wrap_fast_path);
    build_options.addOption(usize, "normalization_buffer_bytes", normalization_buffer_bytes);

    const zunic = b.addModule("zunic", .{
        .root_source_file = b.path("src/root.zig"),
    });
    zunic.addImport("build_options", build_options.createModule());
    const test_step = b.step("test", "Run zunic tests");
    const transition_step = b.step("line-break-tests", "Run line-break machine protocol tests");
    const roots = [_][]const u8{
        "src/root_test.zig",
        "src/conformance_test.zig",
        "src/wrap_test.zig",
        "src/wrap_regression_test.zig",
        "src/scan_test.zig",
        "src/word_test.zig",
        "src/normalization_test.zig",
        "src/line_break.zig",
        "src/utf8.zig",
    };
    for (roots) |root| {
        const test_mod = b.createModule(.{
            .root_source_file = b.path(root),
            .target = target,
            .optimize = optimize,
        });
        if (!std.mem.eql(u8, root, "src/line_break.zig")) test_mod.addImport("zunic", zunic);
        test_mod.addImport("build_options", build_options.createModule());
        const run_test = b.addRunArtifact(b.addTest(.{ .root_module = test_mod }));
        test_step.dependOn(&run_test.step);
        if (std.mem.eql(u8, root, "src/line_break.zig")) transition_step.dependOn(&run_test.step);
    }

    // Keep the >u16 counter regression in the normal gate without running
    // the small-buffer stress fixtures with a quarter-megabyte run limit.
    const large_normalization_options = b.addOptions();
    large_normalization_options.addOption(WrapFastPath, "wrap_fast_path", wrap_fast_path);
    large_normalization_options.addOption(usize, "normalization_buffer_bytes", 262176);
    const large_normalization_mod = b.createModule(.{
        .root_source_file = b.path("src/normalization_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    large_normalization_mod.addImport("build_options", large_normalization_options.createModule());
    const large_normalization_test = b.addRunArtifact(b.addTest(.{
        .root_module = large_normalization_mod,
        .filters = &.{"large configured runs"},
    }));
    test_step.dependOn(&large_normalization_test.step);
    b.step("test-normalization-large", "Test normalization counters beyond u16 capacity")
        .dependOn(&large_normalization_test.step);

    const regression_mod = b.createModule(.{
        .root_source_file = b.path("src/wrap_regression_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    regression_mod.addImport("zunic", zunic);
    regression_mod.addImport("build_options", build_options.createModule());
    const regression_step = b.step("wrap-regressions", "Run wrapper regression tests");
    regression_step.dependOn(&b.addRunArtifact(b.addTest(.{ .root_module = regression_mod })).step);

    const exhaustive_mod = b.createModule(.{
        .root_source_file = b.path("src/wrap_exhaustive_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    exhaustive_mod.addImport("zunic", zunic);
    exhaustive_mod.addImport("build_options", build_options.createModule());
    const exhaustive_step = b.step("wrap-exhaustive", "Run the full-alphabet wrapping sweep");
    exhaustive_step.dependOn(&b.addRunArtifact(b.addTest(.{ .root_module = exhaustive_mod })).step);

    const benchmark_mod = b.createModule(.{
        .root_source_file = b.path("src/benchmark.zig"),
        .target = target,
        .optimize = optimize,
    });
    benchmark_mod.addImport("zunic", zunic);
    const benchmark = b.addExecutable(.{
        .name = "zunic-benchmark",
        .root_module = benchmark_mod,
    });
    const run_benchmark = b.addRunArtifact(benchmark);
    if (b.args) |args| run_benchmark.addArgs(args);
    const benchmark_step = b.step("benchmark", "Run zunic benchmarks");
    benchmark_step.dependOn(&run_benchmark.step);
}
