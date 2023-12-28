const std = @import("std");
const builtin = @import("builtin");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});

    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "vulkan-tutorial-zig",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    const vk_lib_name = if (target.getOsTag() == .windows) "vulkan-1" else "vulkan";

    exe.linkSystemLibrary(vk_lib_name);
    exe.linkSystemLibrary("glfw.3");

    if (b.env_map.get("VK_SDK_PATH")) |path| {
        exe.addLibraryPath(.{ .cwd_relative = std.fmt.allocPrint(b.allocator, "{s}/lib", .{path}) catch @panic("OOM") });
        exe.addIncludePath(.{ .cwd_relative = std.fmt.allocPrint(b.allocator, "{s}/include", .{path}) catch @panic("OOM") });
    }

    //exe.addIncludePath(.{ .path = "thirdparty/vma/" });
    const vert = std.build.FileSource.relative("shaders/vert.spv");
    exe.addAnonymousModule("shaders/vert.spv", .{
        .source_file = vert,
    });

    const frag = std.build.FileSource.relative("shaders/frag.spv");
    exe.addAnonymousModule("shaders/frag.spv", .{
        .source_file = frag,
    });
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const unit_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    const run_unit_tests = b.addRunArtifact(unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);
}
