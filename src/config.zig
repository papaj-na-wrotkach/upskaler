	const std = @import("std");

pub const Config = struct {
	host: []const u8 = "::",
	port: u16 = 0,

	const Self = @This();

	pub fn addLayer(self: *Self, layer: ConfigLayer) void {
		inline for (std.meta.fields(ConfigLayer)) |field| {
			if (@field(layer, field.name)) |override|
				@field(self, field.name) = override;
		}
	}
};

pub const ConfigLayer = struct {
	host: ?[]const u8 = null,
	port: ?u16 = null,

	const Self = @This();

	pub fn fromSlice(allocator: std.mem.Allocator, slice: [:0]const u8, options: std.zon.parse.Options) !Self {
		var config_parse_status: std.zon.parse.Status = .{};
		defer config_parse_status.deinit(allocator);
		const config_file = std.zon.parse.fromSlice(ConfigLayer, allocator, slice, &config_parse_status, options) catch |err| {
			switch (err) {
				error.ParseZon => {
					std.debug.print("failed to parse config file: {}", .{ config_parse_status });
				},
				else => {},
			}
			return err;
		};

		return config_file;
	}

	//TODO: implement methods that return ConfigLayer from other sources (command line arguments, environment)
};
