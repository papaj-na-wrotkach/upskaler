const std = @import("std");
const UpskalerPlugin = @import("plugskaler-api").UpskalerPlugin;

const PluginManager = struct {

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

pub fn main() !void {
	var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
	defer arena.deinit();

	var plugin_registry = std.StringHashMap(PluginManager).init(arena.allocator());
	defer plugin_registry.deinit();

	var gp = std.heap.GeneralPurposeAllocator(.{}).init;
	const gpa = gp.allocator();
	defer _ = gp.deinit();

	const exe_path = try std.fs.selfExeDirPathAlloc(gpa);
	defer gpa.free(exe_path);
	const plugin_path_base = try std.fs.path.join(gpa, &[_][]const u8{ exe_path, "..", "lib" });
	defer gpa.free(plugin_path_base);

	const plugins = [_][]const u8{ "realcugan", "waifu2x" };
	inline for(plugins) |name| {
		const res = try plugin_registry.getOrPut(name);
		if (res.found_existing) {
			std.debug.print("Refusing to register duplicate plugin.\n", .{});
			return;
		}

		const plugin_path = try std.fs.path.join(gpa, &[_][]const u8{ plugin_path_base, "/libplugskaler-" ++ name ++ ".so" });
		defer gpa.free(plugin_path);
		res.value_ptr.* = try PluginManager.init(plugin_path);
	}
	defer {
		var it = plugin_registry.valueIterator();
		while (it.next()) |pm| {
			pm.deinit();
		}
	}

	var it = plugin_registry.iterator();
	while (it.next()) |kv| {
		std.debug.print("{s}: {}\n", .{ kv.key_ptr.*, kv.value_ptr.plugin });
	}
}
