const std = @import("std");

pub fn build(b: *std.Build) void {
	const target = b.standardTargetOptions(.{});
	const optimize = b.standardOptimizeOption(.{});

	// Include the dependencies.

	// the plugin API

	const libplugskaler_api = b.dependency("plugskaler_api", .{
		.target = target,
		.optimize = optimize,
	});
	const plugskaler_api = libplugskaler_api.module("plugskaler-api");

	// built-in plugins

	const opt_build_plugins = b.option(bool, "build-plugins", "Build the plugins and install them as artifacts") orelse false;
	if (opt_build_plugins) {
		// Include the lazy dependencies

		const libplugskaler_realcugan = b.lazyDependency("plugskaler_realcugan", .{
			.target = target,
			.optimize = optimize,
		});
		const libplugskaler_waifu2x = b.lazyDependency("plugskaler_waifu2x", .{
			.target = target,
			.optimize = optimize,
		});

		// Install the dynamic libraries.

		b.installArtifact(libplugskaler_realcugan.?.artifact("plugskaler-realcugan"));
		b.installArtifact(libplugskaler_waifu2x.?.artifact("plugskaler-waifu2x"));
	}

	// ZZZ
	const libzzz = b.dependency("zzz", .{
		.target = target,
		.optimize = optimize,
	});
	const zzz = libzzz.module("zzz");

	// Define the library module of the app (unused for now).

	const mod = b.addModule("upskaler", .{
		.root_source_file = b.path("src/root.zig"),
		.target = target,
		.imports = &.{
			.{ .name = "plugskaler-api", .module = plugskaler_api },
		},
	});

	// Define the executable.

	const exe = b.addExecutable(.{
		.name = "upskaler",
		.root_module = b.createModule(.{
			.root_source_file = b.path("src/main.zig"),
			.target = target,
			.optimize = optimize,
			.imports = &.{
				.{ .name = "upskaler", .module = mod }, // the library module of the app
				.{ .name = "plugskaler-api", .module = plugskaler_api }, // the plugin API
				.{ .name = "zzz", .module = zzz },
			},
		}),
	});

	const install_step = b.getInstallStep();

	// Install the executable and config.

	b.installArtifact(exe);
	install_step.dependOn(&b.addInstallFileWithDir(b.path("conf.zon"), .{ .custom = b.pathJoin(&[_][]const u8{ "etc", "upskaler" }) }, "conf.zon" ).step);

	// Create empty directory for drop-in configuration files.

	var dropin_conf_dir_step = b.step("mkdir_conf_d", "Create empty directory for drop-in configuration files.");
	install_step.dependOn(dropin_conf_dir_step);
	dropin_conf_dir_step.makeFn = struct {
		fn func(step: *std.Build.Step, _: std.Build.Step.MakeOptions) anyerror!void  {
			const full_path = step.owner.getInstallPath(.{ .custom = "etc" }, step.owner.pathJoin(&[_][]const u8{ "upskaler", "conf.d" }));
			try std.fs.cwd().makePath(full_path);
		}
	}.func;

	// Enable the app to run with `zig build run`.

	const run_step = b.step("run", "Run the app");

	// Use the built executable artifact for `zig build run`.

	const run_cmd = b.addRunArtifact(exe);
	run_step.dependOn(&run_cmd.step);
	// Install the executable and plugins before using them.
	run_cmd.step.dependOn(install_step);
	if (b.args) |args| {
		// Pass the arguments to the executable.
		run_cmd.addArgs(args);
	}

	//TODO: Configure and use tests.

	// Creates an executable that will run `test` blocks from the provided module.
	// Here `mod` needs to define a target, which is why earlier we made sure to
	// set the releative field.
	const mod_tests = b.addTest(.{
			.root_module = mod,
	});

	// A run step that will run the test executable.
	const run_mod_tests = b.addRunArtifact(mod_tests);

	// Creates an executable that will run `test` blocks from the executable's
	// root module. Note that test executables only test one module at a time,
	// hence why we have to create two separate ones.
	const exe_tests = b.addTest(.{
			.root_module = exe.root_module,
	});

	// A run step that will run the second test executable.
	const run_exe_tests = b.addRunArtifact(exe_tests);

	// A top level step for running all tests. dependOn can be called multiple
	// times and since the two run steps do not depend on one another, this will
	// make the two of them run in parallel.
	const test_step = b.step("test", "Run tests");
	test_step.dependOn(&run_mod_tests.step);
	test_step.dependOn(&run_exe_tests.step);

	// Just like flags, top level steps are also listed in the `--help` menu.
	//
	// The Zig build system is entirely implemented in userland, which means
	// that it cannot hook into private compiler APIs. All compilation work
	// orchestrated by the build system will result in other Zig compiler
	// subcommands being invoked with the right flags defined. You can observe
	// these invocations when one fails (or you pass a flag to increase
	// verbosity) to validate assumptions and diagnose problems.
	//
	// Lastly, the Zig build system is relatively simple and self-contained,
	// and reading its source code will allow you to master it.
}
