const std = @import("std");
const fmt = std.fmt;

const Import = std.Build.Module.Import;

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // const dep_lazy = b.dependency("lazy", .{
    //     .target = target,
    //     .optimize = optimize,
    // });

    const dep_cow = b.dependencyFromBuildZig(@import("cow"), .{
        .target = target,
        .optimize = optimize,
    });

    // const lazypath = dep_cow.path("cow");
    // std.debug.print("lazypath: {s}\n", .{lazypath.getPath(b)});

    // const dep_cow = b.dependency("cow", .{
    //     .target = target,
    //     .optimize = optimize,
    // });
    const dep_test_zon = b.dependency("test_zon", .{
        .target = target,
        .optimize = optimize,
    });

    // const AddImport = struct {
    //     name: []const u8,
    //     module: *std.Build.Module,
    // };

    const import_test_zon = Import{ .name = "test_zon", .module = dep_test_zon.module("test_zon") };
    const import_cow = Import{ .name = "cow", .module = dep_cow.module("cow") };

    const mod_zraw = b.addModule("zraw", .{
        .root_source_file = .{ .path = "src/root.zig" },
        .imports = &.{
            import_test_zon,
            import_cow,
        },
    });
    _ = mod_zraw;

    // mod_z

    const AddTest = struct {
        path: []const u8,
        imports: []const Import,
    };

    const step_test_all = b.step("test", "Run unit tests");

    const add_tests_list = [_]AddTest{
        .{ .path = "src/root.zig", .imports = &.{import_test_zon} },
        .{ .path = "src/fetch.zig", .imports = &.{import_cow} },
    };

    for (&add_tests_list) |opts| {
        const unit_tests = b.addTest(.{
            .root_source_file = .{ .path = opts.path },
            .target = target,
            .optimize = optimize,
        });

        for (opts.imports) |import| {
            unit_tests.root_module.addImport(import.name, import.module);
        }

        const run_unit_tests = b.addRunArtifact(unit_tests);
        step_test_all.dependOn(&run_unit_tests.step);

        run_unit_tests.step.dependOn(b.getInstallStep());
    }

    // {
    //     const unit_tests = b.addTest(.{
    //         .root_source_file = .{ .path = "src/root.zig" },
    //         .target = target,
    //         .optimize = optimize,
    //     });

    //     unit_tests.root_module.addImport("test_zon", dep_test_zon.module("test_zon"));

    //     const run_unit_tests = b.addRunArtifact(unit_tests);
    //     step_test_all.dependOn(&run_unit_tests.step);

    //     run_unit_tests.step.dependOn(b.getInstallStep());
    // }

    // {
    //     const unit_tests = b.addTest(.{
    //         .root_source_file = .{ .path = "src/fetch.zig" },
    //         .target = target,
    //         .optimize = optimize,
    //     });

    //     unit_tests.root_module.addImport("cow", dep_cow.module("cow"));

    //     const run_unit_tests = b.addRunArtifact(unit_tests);
    //     step_test_all.dependOn(&run_unit_tests.step);

    //     run_unit_tests.step.dependOn(b.getInstallStep());
    // }

    // const addModuleCow = struct {
    //     fn  f(compile: *std.Build.Step.Compile) void {
    //        compile.addModule("cow", )
    //     }
    // }.f;

    // {
    //     const lib_zraw = b.addStaticLibrary(.{
    //         .name = "zraw",
    //         .root_source_file = .{ .path = "src/root.zig" },
    //         .target = target,
    //         .optimize = optimize,
    //     });
    //     lib_zraw.addModule("lazy", dep_lazy.module("lazy"));
    //     b.installArtifact(lib_zraw);
    // }

    // {
    //     const compile = b.addStaticLibrary(.{
    //         .name = "foo",
    //         .root_source_file = .{ .path = "src/foo.zig" },
    //         .target = target,
    //         .optimize = optimize,
    //     });
    //     compile.addModule("swiss_table", dep_swiss_table.module("swiss_table"));
    //     b.installArtifact(compile);
    // }

    // =============================

    // const lib = b.addStaticLibrary(.{
    //     .name = "zraw",
    //     // In this case the main source file is merely a path, however, in more
    //     // complicated build scripts, this could be a generated file.
    //     .root_source_file = .{ .path = "src/root.zig" },
    //     .target = target,
    //     .optimize = optimize,
    // });

    // // This declares intent for the library to be installed into the standard
    // // location when the user invokes the "install" step (the default step when
    // // running `zig build`).
    // b.installArtifact(lib);

    // const exe = b.addExecutable(.{
    //     .name = "zraw",
    //     .root_source_file = .{ .path = "src/main.zig" },
    //     .target = target,
    //     .optimize = optimize,
    // });

    // // This declares intent for the executable to be installed into the
    // // standard location when the user invokes the "install" step (the default
    // // step when running `zig build`).
    // b.installArtifact(exe);

    // // This *creates* a Run step in the build graph, to be executed when another
    // // step is evaluated that depends on it. The next line below will establish
    // // such a dependency.
    // const run_cmd = b.addRunArtifact(exe);

    // // By making the run step depend on the install step, it will be run from the
    // // installation directory rather than directly from within the cache directory.
    // // This is not necessary, however, if the application depends on other installed
    // // files, this ensures they will be present and in the expected location.
    // run_cmd.step.dependOn(b.getInstallStep());

    // // This allows the user to pass arguments to the application in the build
    // // command itself, like this: `zig build run -- arg1 arg2 etc`
    // if (b.args) |args| {
    //     run_cmd.addArgs(args);
    // }

    // // This creates a build step. It will be visible in the `zig build --help` menu,
    // // and can be selected like this: `zig build run`
    // // This will evaluate the `run` step rather than the default, which is "install".
    // const run_step = b.step("run", "Run the app");
    // run_step.dependOn(&run_cmd.step);

    // // Creates a step for unit testing. This only builds the test executable
    // // but does not run it.
    // const lib_unit_tests = b.addTest(.{
    //     .root_source_file = .{ .path = "src/root.zig" },
    //     .target = target,
    //     .optimize = optimize,
    // });

    // const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    // const exe_unit_tests = b.addTest(.{
    //     .root_source_file = .{ .path = "src/main.zig" },
    //     .target = target,
    //     .optimize = optimize,
    // });

    // const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    // // Similar to creating the run step earlier, this exposes a `test` step to
    // // the `zig build --help` menu, providing a way for the user to request
    // // running the unit tests.
    // const test_step = b.step("test", "Run unit tests");
    // test_step.dependOn(&run_lib_unit_tests.step);
    // test_step.dependOn(&run_exe_unit_tests.step);
}
