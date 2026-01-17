const std = @import("std");

pub fn build(b: *std.Build) void {
	const target = b.standardTargetOptions(.{});
	const optimize = b.standardOptimizeOption(.{});

	const libplugskaler_api = b.dependency("plugskaler_api", .{
		.target = target,
		.optimize = optimize,
	});
	const plugskaler_api = libplugskaler_api.module("plugskaler-api");

	const plugskaler_realcugan = b.addModule("plugskaler-waifu2x", .{
		.root_source_file = b.path("root.zig"),
		.target = target,
		.optimize = optimize,
		.imports = &.{
			.{ .name = "plugskaler-api", .module = plugskaler_api},
		},
	});

	const libplugskaler_realcugan = b.addSharedLibrary(.{
		.name = "plugskaler-waifu2x",
		.version = .{ .major = 0, .minor = 0, .patch = 1, },
		.root_module = plugskaler_realcugan,
	});

	b.installArtifact(libplugskaler_realcugan);
}
