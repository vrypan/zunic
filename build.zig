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

    // The internal module graph. A module reaches only what it is granted an
    // import for here, so an undeclared dependency is a compile error rather
    // than something a reviewer has to catch. It is acyclic by construction:
    // `tables` and `types` are independent foundations with no module imports.
    //
    // `tables` stays one module on purpose. Its `Record` fuses grapheme,
    // width and line-break facts into a single `u32` so a scanner resolves a
    // scalar once and answers all three questions from that entry; splitting
    // it per engine would cost either duplicated tables or a lookup apiece.
    // See docs/internals/README.md.
    //
    // These are `createModule`, not `addModule`: only `zunic` is part of the
    // package's public surface, and a dependent must not be able to reach
    // past it to an internal module by name.
    const Modules = struct {
        types: *std.Build.Module,
        tables: *std.Build.Module,
        cp: *std.Build.Module,
        encoding: *std.Build.Module,
        segmentation: *std.Build.Module,
        linebreak: *std.Build.Module,
        normalization: *std.Build.Module,
        layout: *std.Build.Module,
        text: *std.Build.Module,

        /// Explicit facade dependencies: new internal modules are not automatically granted.
        fn addFacadeImports(self: @This(), module: *std.Build.Module) void {
            module.addImport("types", self.types);
            module.addImport("tables", self.tables);
            module.addImport("cp", self.cp);
            module.addImport("encoding", self.encoding);
            module.addImport("segmentation", self.segmentation);
            module.addImport("linebreak", self.linebreak);
            module.addImport("normalization", self.normalization);
            module.addImport("layout", self.layout);
            module.addImport("text", self.text);
        }
    };

    // Built per options module rather than once: `-Dnormalization-buffer-bytes`
    // is compiled into `normalization`, and the large-buffer test target needs
    // its own instance at a different setting. Sharing one would quietly test
    // the default.
    const buildModules = struct {
        fn call(owner: *std.Build, options: *std.Build.Module) Modules {
            const types = owner.createModule(.{ .root_source_file = owner.path("src/types.zig") });
            const tables = owner.createModule(.{ .root_source_file = owner.path("src/tables/tables.zig") });

            const cp = owner.createModule(.{ .root_source_file = owner.path("src/cp/cp.zig") });
            cp.addImport("tables", tables);

            const encoding = owner.createModule(.{ .root_source_file = owner.path("src/encoding/encoding.zig") });
            encoding.addImport("tables", tables);

            const segmentation = owner.createModule(.{ .root_source_file = owner.path("src/segmentation/segmentation.zig") });
            segmentation.addImport("tables", tables);
            segmentation.addImport("encoding", encoding);

            const linebreak = owner.createModule(.{ .root_source_file = owner.path("src/linebreak/linebreak.zig") });
            linebreak.addImport("tables", tables);
            linebreak.addImport("encoding", encoding);

            const normalization = owner.createModule(.{ .root_source_file = owner.path("src/normalization/normalization.zig") });
            normalization.addImport("tables", tables);
            normalization.addImport("encoding", encoding);
            normalization.addImport("build_options", options);

            const layout = owner.createModule(.{ .root_source_file = owner.path("src/layout/layout.zig") });
            layout.addImport("tables", tables);
            layout.addImport("encoding", encoding);
            layout.addImport("segmentation", segmentation);
            layout.addImport("linebreak", linebreak);
            layout.addImport("build_options", options);

            const text = owner.createModule(.{ .root_source_file = owner.path("src/text/text.zig") });
            text.addImport("cp", cp);
            text.addImport("types", types);
            text.addImport("encoding", encoding);
            text.addImport("segmentation", segmentation);
            text.addImport("normalization", normalization);
            text.addImport("layout", layout);

            return .{
                .types = types,
                .tables = tables,
                .cp = cp,
                .encoding = encoding,
                .segmentation = segmentation,
                .linebreak = linebreak,
                .normalization = normalization,
                .layout = layout,
                .text = text,
            };
        }
    }.call;

    // One instance, shared everywhere: a file may belong to exactly one
    // module, so repeated `createModule()` calls on the same options would
    // make rival modules rooted at the same generated file.
    const options_module = build_options.createModule();
    const internal = buildModules(b, options_module);

    const zunic = b.addModule("zunic", .{
        .root_source_file = b.path("src/root.zig"),
    });
    zunic.addImport("build_options", options_module);
    internal.addFacadeImports(zunic);

    const test_step = b.step("test", "Run every test");
    const docs_step = b.step("docs-test", "Run documentation examples");
    const transition_step = b.step("line-break-tests", "Run line-break machine protocol tests");

    // Which modules a test root may reach, and which per-module step runs it.
    //
    // The grants are deliberately narrow rather than "all of them". A test is
    // the first place a boundary erodes, and a root that can see every module
    // can quietly grow a dependency the library itself is not allowed. It also
    // keeps the compile cache honest: editing `normalization` should not
    // rebuild the word tests.
    //
    // Note what `zunic` costs. It re-exports every module, so any root that
    // needs the public API depends on all of them whatever this table says;
    // only the roots that test an engine directly are genuinely narrow.
    const Grant = enum { none, api, cp, text, tables, encoding, segmentation, linebreak, normalization, layout };
    const TestRoot = struct {
        path: []const u8,
        /// Step suffix: `zig build test-<group>` runs just this group.
        group: []const u8,
        extra_group: ?[]const u8 = null,
        grants: []const Grant,
    };
    const test_roots = [_]TestRoot{
        .{ .path = "src/cp/cp_test.zig", .group = "cp", .grants = &.{ .cp, .tables } },
        .{ .path = "src/text/text_test.zig", .group = "text", .grants = &.{ .text, .cp, .layout } },
        .{ .path = "src/encoding/utf8.zig", .group = "encoding", .grants = &.{.none} },
        .{ .path = "src/linebreak/linebreak.zig", .group = "linebreak", .grants = &.{ .tables, .encoding } },
        .{ .path = "src/word_test.zig", .group = "segmentation", .grants = &.{ .tables, .segmentation } },
        .{ .path = "src/scan_test.zig", .group = "layout", .grants = &.{ .tables, .encoding, .segmentation, .linebreak, .layout } },
        .{ .path = "src/wrap_test.zig", .group = "layout", .grants = &.{.api} },
        .{ .path = "src/wrap_regression_test.zig", .group = "layout", .grants = &.{.api} },
        .{ .path = "src/normalization_test.zig", .group = "normalization", .grants = &.{ .api, .tables, .encoding, .normalization } },
        .{ .path = "src/conformance_test.zig", .group = "conformance", .grants = &.{ .api, .segmentation, .normalization } },
        .{ .path = "src/root_test.zig", .group = "api", .grants = &.{.api} },
        .{ .path = "src/cp/unicode_properties_test.zig", .group = "unicode-properties", .extra_group = "cp", .grants = &.{.cp} },
        .{ .path = "src/case_folding_test.zig", .group = "case-folding", .extra_group = "cp", .grants = &.{.cp} },
        .{ .path = "src/grapheme_stream_test.zig", .group = "grapheme-stream", .extra_group = "segmentation", .grants = &.{.segmentation} },
        .{ .path = "src/text/trim_test.zig", .group = "trim", .extra_group = "text", .grants = &.{ .text, .cp } },
        .{ .path = "src/text/ascii_test.zig", .group = "ascii", .extra_group = "text", .grants = &.{ .text, .encoding } },
        .{ .path = "docs/examples.zig", .group = "api", .grants = &.{.api} },
    };

    var group_steps = std.StringHashMap(*std.Build.Step).init(b.allocator);
    for (test_roots) |root| {
        const test_mod = b.createModule(.{
            .root_source_file = b.path(root.path),
            .target = target,
            .optimize = optimize,
        });
        for (root.grants) |grant| switch (grant) {
            .none => {},
            .api => test_mod.addImport("zunic", zunic),
            .cp => test_mod.addImport("cp", internal.cp),
            .text => test_mod.addImport("text", internal.text),
            .tables => test_mod.addImport("tables", internal.tables),
            .encoding => test_mod.addImport("encoding", internal.encoding),
            .segmentation => test_mod.addImport("segmentation", internal.segmentation),
            .linebreak => test_mod.addImport("linebreak", internal.linebreak),
            .normalization => test_mod.addImport("normalization", internal.normalization),
            .layout => test_mod.addImport("layout", internal.layout),
        };
        test_mod.addImport("build_options", options_module);
        const run_test = b.addRunArtifact(b.addTest(.{ .root_module = test_mod }));
        test_step.dependOn(&run_test.step);

        // Reuse each test artifact across focused targets; the aggregate runs it once.
        for ([_]?[]const u8{ root.group, root.extra_group }) |maybe_group| {
            const group_name = maybe_group orelse continue;
            const group = group_steps.get(group_name) orelse blk: {
                const name = b.fmt("test-{s}", .{group_name});
                const step = b.step(name, b.fmt("Run the {s} tests only", .{group_name}));
                group_steps.put(group_name, step) catch @panic("OOM");
                break :blk step;
            };
            group.dependOn(&run_test.step);
        }

        if (std.mem.eql(u8, root.path, "docs/examples.zig")) docs_step.dependOn(&run_test.step);
        if (std.mem.eql(u8, root.path, "src/linebreak/linebreak.zig")) transition_step.dependOn(&run_test.step);
    }

    // These focused gates also decode the generated tables independently from
    // the vendored Unicode inputs. Keep them off the aggregate test step so
    // the normal Zig-only suite does not acquire a Python runtime dependency.
    const verify_terminal_properties = b.addSystemCommand(&.{ "python3", "src/tools/test-terminal-properties.py" });
    group_steps.get("unicode-properties").?.dependOn(&verify_terminal_properties.step);
    const verify_numeric_properties = b.addSystemCommand(&.{ "python3", "src/tools/test-numeric-properties.py" });
    group_steps.get("unicode-properties").?.dependOn(&verify_numeric_properties.step);
    const verify_case_folding = b.addSystemCommand(&.{ "python3", "src/tools/test-case-folding.py" });
    group_steps.get("case-folding").?.dependOn(&verify_case_folding.step);

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
    const large_options = large_normalization_options.createModule();
    const large_internal = buildModules(b, large_options);
    large_normalization_mod.addImport("build_options", large_options);
    large_normalization_mod.addImport("tables", large_internal.tables);
    large_normalization_mod.addImport("encoding", large_internal.encoding);
    large_normalization_mod.addImport("normalization", large_internal.normalization);
    const large_zunic = b.createModule(.{ .root_source_file = b.path("src/root.zig") });
    large_zunic.addImport("build_options", large_options);
    large_internal.addFacadeImports(large_zunic);
    large_normalization_mod.addImport("zunic", large_zunic);
    const large_normalization_test = b.addRunArtifact(b.addTest(.{
        .root_module = large_normalization_mod,
        .filters = &.{"large configured runs"},
    }));
    test_step.dependOn(&large_normalization_test.step);
    if (group_steps.get("normalization")) |step| step.dependOn(&large_normalization_test.step);
    b.step("test-normalization-large", "Test normalization counters beyond u16 capacity")
        .dependOn(&large_normalization_test.step);

    const regression_mod = b.createModule(.{
        .root_source_file = b.path("src/wrap_regression_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    regression_mod.addImport("zunic", zunic);
    regression_mod.addImport("build_options", options_module);
    const regression_step = b.step("wrap-regressions", "Run wrapper regression tests");
    regression_step.dependOn(&b.addRunArtifact(b.addTest(.{ .root_module = regression_mod })).step);

    const exhaustive_mod = b.createModule(.{
        .root_source_file = b.path("src/wrap_exhaustive_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    exhaustive_mod.addImport("zunic", zunic);
    exhaustive_mod.addImport("build_options", options_module);
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
