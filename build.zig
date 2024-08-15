const std = @import("std");

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{ .preferred_optimize_mode = .ReleaseFast });

    const game = b.addExecutable(.{
        .name = "life",
        .root_source_file = b.path("main.zig"),
        .target = b.resolveTargetQuery(.{
            .cpu_arch = .wasm32,
            // TODO .cpu_model = .bleeding_edge non-viable
            // https://webassembly.org/features/
            .cpu_features_add = std.Target.wasm.featureSet(&.{
                .atomics,
                .bulk_memory,
                .exception_handling,
                // .extended_const,
                .multivalue,
                .mutable_globals,
                .nontrapping_fptoint,
                .reference_types,
                // .relaxed_simd,
                .sign_ext,
                .simd128,
                // .tail_call,
            }),
            .os_tag = .freestanding,
        }),
        .optimize = optimize,
    });

    game.rdynamic = true;
    game.entry = .disabled;

    const wf = b.addWriteFiles();
    _ = wf.addCopyFile(game.getEmittedBin(), game.out_filename);
    _ = wf.addCopyFile(b.path("index.html"), "index.html");

    const www_dir = b.addInstallDirectory(.{ .source_dir = wf.getDirectory(), .install_dir = .prefix, .install_subdir = "www" });
    b.getInstallStep().dependOn(&www_dir.step);
}
