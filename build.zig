const std = @import("std");

const vkgen = @import("vulkan_zig");

pub fn build(b: *std.Build) void {
    // wasm: cpu_arch .wasm32, os_tag = .freestanding
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    if (target.result.cpu.arch.isWasm()) {
        const lib = b.addExecutable(.{
            .name = "pav",
            .root_module = b.createModule(. {
                .root_source_file = b.path("src/pav.zig"),
                .target = target,
                .optimize = optimize,
            }),
        });
        lib.entry = .disabled;
        lib.rdynamic = true;
        b.installArtifact(lib);
        return;
    }

    const exe = b.addExecutable(.{
        .name = "pav",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/pav_cli.zig"),
            .target = target,
            .link_libc = true,
            .optimize = optimize,
        }),
    });

    const upstream = b.dependency("zlib", .{});
    const zlib = b.addLibrary(.{
        .name = "z",
        .linkage = .static,
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });
    zlib.addCSourceFiles(.{
        .root = upstream.path(""),
        .files = &.{
            "adler32.c",
            "crc32.c",
            "deflate.c",
            "infback.c",
            "inffast.c",
            "inflate.c",
            "inftrees.c",
            "trees.c",
            "zutil.c",
            "compress.c",
            "uncompr.c",
            "gzclose.c",
            "gzlib.c",
            "gzread.c",
            "gzwrite.c",
        },
        .flags = &.{
            "-DHAVE_SYS_TYPES_H",
            "-DHAVE_STDINT_H",
            "-DHAVE_STDDEF_H",
            "-DZ_HAVE_UNISTD_H",
        },
    });
    zlib.installHeadersDirectory(upstream.path(""), "", .{
        .include_extensions = &.{
            "zconf.h",
            "zlib.h",
        },
    });

    const registry = b.dependency("vulkan_headers", .{}).path("registry/vk.xml");
    const vulkan = b.dependency("vulkan_zig", .{
        .registry = registry,
    }).module("vulkan-zig");

    exe.root_module.addImport("vulkan", vulkan);
    exe.linkLibrary(zlib);
    exe.linkSystemLibrary("vulkan");
    b.installArtifact(exe);
    
    const run_step = b.step("run", "run it");
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const exe_tests = b.addTest(.{ .root_module = exe.root_module });
    const run_exe_tests = b.addRunArtifact(exe_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_exe_tests.step);
}
