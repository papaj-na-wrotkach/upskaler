const std = @import("std");

pub const config = @import("config.zig");
pub const PluginManager = @import("plugin_manager.zig").PluginManager;

pub const AppContext = struct {
	config: *const config.Config,
	plugin_registry: *const std.StringHashMap(PluginManager),
};
