const std = @import("std");

const plugskaler = @import("plugskaler-api");
const UpskalerPlugin = plugskaler.UpskalerPlugin;

pub const PluginManager = struct {
	lib: std.DynLib,
	plugin: *UpskalerPlugin,

	const Self = @This();
	const Error = std.DynLib.Error || error{ SymbolNotFound };

	pub fn init(path: []const u8) Error!Self {
		var lib = try std.DynLib.open(path);
		return Self{
			.lib = lib,
			.plugin = lib.lookup(*UpskalerPlugin, "plugin") orelse {
				defer lib.close();
				return error.SymbolNotFound;
			},
		};
	}

	pub fn deinit(self: *Self) void {
		self.lib.close();
	}
};
