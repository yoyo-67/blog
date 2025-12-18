const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimaizer = b.standardOptimizeOption(.{});
    const root_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimaizer,
    });

    const exe = b.addExecutable(.{
        .name = "comp",
        .root_module = root_module,
    });

    b.installArtifact(exe);

    const runCmd = b.addRunArtifact(exe);
    runCmd.step.dependOn(b.getInstallStep());

    const runStep = b.step("run", "run the compiler");
    runStep.dependOn(&runCmd.step);

    const unitTest = b.addTest(.{
        .root_module = root_module,
    });
    const runUnitTest = b.addRunArtifact(unitTest);
    const runTestStep = b.step("test", "test the compiler");
    runTestStep.dependOn(&runUnitTest.step);
}
