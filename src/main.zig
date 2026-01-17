const std = @import("std");

const plugskaler = @import("plugskaler-api");
const UpskalerPlugin = plugskaler.UpskalerPlugin;
const upskaler = @import("upskaler");
const Config = upskaler.config.Config;
const ConfigLayer = upskaler.config.ConfigLayer;
const zzz = @import("zzz");
const http = zzz.HTTP;
const tardy = zzz.tardy;

const Tardy = tardy.Tardy(.io_uring);

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

fn base_handler(ctx: *const http.Context, _: void) !http.Respond {
	return ctx.response.apply(.{
		.status = .OK,
		.mime = http.Mime.HTML,
		.body = "Hello, world!",
	});
}

pub fn main() !void {
	// Allocators!

	var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
	defer arena.deinit();
	var gp = std.heap.GeneralPurposeAllocator(.{ .thread_safe = true }).init;
	const gpa = gp.allocator();
	defer std.debug.print("GPA heap check: {}\n", .{ gp.deinit() });

	// Read the config file

	const file = try std.fs.cwd().openFile("conf.zon", .{});
	defer file.close();

	const buffer = try gpa.allocSentinel(u8, (try file.stat()).size, 0);
	defer gpa.free(buffer);

	_ = try file.readAll(buffer);

	// Construct the Config struct
	var config: Config = .{};
	config.addLayer(try ConfigLayer.fromSlice(gpa, buffer, .{}));

	var plugin_registry = std.StringHashMap(PluginManager).init(arena.allocator());
	defer plugin_registry.deinit();

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

	var t = try Tardy.init(gpa, .{ .threading = .auto });
	defer t.deinit();

	var router = try http.Router.init(gpa, &.{
		http.Route.init("/").get({}, base_handler).layer(),
	}, .{});
	defer router.deinit(gpa);

	// create socket for tardy
	var socket = try tardy.Socket.init(.{ .tcp = .{ .host = config.host, .port = config.port } });
	defer socket.close_blocking();
	try socket.bind();
	try socket.listen(4096);

	const EntryParams = struct {
		router: *const http.Router,
		socket: tardy.Socket,
	};

	try t.entry(
		EntryParams{ .router = &router, .socket = socket },
		struct {
			fn entry(rt: *tardy.Runtime, p: EntryParams) !void {
				var server = http.Server.init(.{
					.stack_size = 1024 * 1024 * 4,
					.socket_buffer_bytes = 1024 * 2,
					.keepalive_count_max = null,
					.connection_count_max = 10,
				});
				try server.serve(rt, p.router, .{ .normal = p.socket });
			}
		}.entry,
	);
}
