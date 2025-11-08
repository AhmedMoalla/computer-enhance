const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const src_path = try std.fs.cwd().realpathAlloc(b.allocator, "src");
    var src = try std.fs.openDirAbsolute(src_path, .{ .iterate = true });

    var it = src.iterateAssumeFirstIteration();
    while (try it.next()) |dir| {
        const exe = b.addExecutable(.{
            .name = dir.name,
            .root_module = b.createModule(.{
                .root_source_file = b.path(try std.fmt.allocPrint(b.allocator, "src/{s}/main.zig", .{dir.name})),
                .target = target,
                .optimize = optimize,
                .imports = &.{},
            }),
        });

        b.installArtifact(exe);

        const run_step = b.step(dir.name, try std.fmt.allocPrint(b.allocator, "Run {s}", .{dir.name}));
        const run_cmd = b.addRunArtifact(exe);
        run_step.dependOn(&run_cmd.step);
        if (b.args) |args| {
            run_cmd.addArgs(args);
        }

        const exe_tests = b.addTest(.{
            .root_module = exe.root_module,
        });
        const run_exe_tests = b.addRunArtifact(exe_tests);

        const test_step = b.step(
            try std.fmt.allocPrint(b.allocator, "test-{s}", .{dir.name}),
            try std.fmt.allocPrint(b.allocator, "Test {s}", .{dir.name}),
        );
        test_step.dependOn(&run_exe_tests.step);
    }
}
