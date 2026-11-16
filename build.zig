const std = @import("std");
const Translator = @import("translate_c").Translator;

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{ .preferred_optimize_mode = .ReleaseSafe });
    const wren_src = b.dependency("wren", .{});
    const translate_c = b.dependency("translate_c", .{});
    const t: Translator = .init(translate_c, .{
        .c_source_file = wren_src.path("src/include/wren.h"),
        .target = target,
        .optimize = optimize,
    });
    t.addIncludePath(wren_src.path("src/include"));
    t.addIncludePath(wren_src.path("src/vm"));
    t.defineCMacro("WREN_OPT_META", "0");
    t.defineCMacro("WREN_OPT_RANDOM", "0");
    t.defineCMacro("WREN_COMPUTED_GOTO", "1");
    t.mod.addCSourceFiles(.{
        .files = &.{
            "wren_compiler.c",
            "wren_core.c",
            "wren_primitive.c",
            "wren_utils.c",
            "wren_value.c",
            "wren_vm.c",
        },
        .root = wren_src.path("src/vm"),
        .flags = &.{"-std=c99"}
    });
    if (optimize == .debug) {
        t.defineCMacro("WREN_DEBUG_TRACE_INSTRUCTIONS", "1");
        t.mod.addCSourceFile(.{ .file = wren_src.path("src/vm/wren_debug.c") });
    }

    const wren_mod = b.addModule("wren", .{
        .root_source_file = b.path("wren.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "c", .module = t.mod },
        },
    });

    // TODO: Add the wren-cli as a lazy dep and build the wren cli
    //
    // const wren = b.addExecutable(.{
    //     .name = "wren",
    //     .root_module = wren_mod,
    // });
    // b.installArtifact(wren);

    // const run_step = b.step("run", "Run the wren vm");
    // const run_cmd = b.addRunArtifact(wren);
    // run_step.dependOn(&run_cmd.step);
    //
    // run_cmd.step.dependOn(b.getInstallStep());
    //
    // run_cmd.addPassthruArgs();

    const test_step = b.step("test", "Run tests");
    const mod_tests = b.addTest(.{
        .root_module = wren_mod,
    });

    const run_mod_tests = b.addRunArtifact(mod_tests);
    test_step.dependOn(&run_mod_tests.step);
}
