const std = @import("std");

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{ .preferred_optimize_mode = .ReleaseFast });
    const strip = switch (optimize) {
        .Debug => false,
        .ReleaseSafe, .ReleaseFast, .ReleaseSmall => true,
    };

    const life = b.addExecutable(.{
        .name = "life",
        .root_module = b.createModule(.{
            .root_source_file = b.path("life.zig"),
            .target = b.resolveTargetQuery(.{
                .cpu_arch = .wasm32,
                .cpu_features_add = std.Target.wasm.featureSet(&.{
                    .bulk_memory,
                    .multivalue,
                    .mutable_globals,
                    .nontrapping_fptoint,
                    .reference_types,
                    .sign_ext,
                    .simd128,
                }),
                .os_tag = .freestanding,
            }),
            .optimize = optimize,
            .strip = strip,
        }),
    });

    life.root_module.export_symbol_names = &.{ "init", "frame" };
    life.entry = .disabled;

    const wf = b.addWriteFiles();
    _ = wf.addCopyFile(life.getEmittedBin(), life.out_filename);
    _ = wf.addCopyFile(b.path("index.html"), "index.html");
    _ = wf.addCopyFile(b.path("favicon.png"), "favicon.png");

    const www_dir = b.addInstallDirectory(.{ .source_dir = wf.getDirectory(), .install_dir = .prefix, .install_subdir = "www" });
    b.getInstallStep().dependOn(&www_dir.step);
}
