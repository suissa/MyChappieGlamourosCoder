const std = @import("std");
const prov = @import("llm/provider.zig");

pub const AppConfig = struct {
    provider_type: prov.ProviderType = .mock,
    model: []const u8 = "mock-chappie-v1",
    api_key: ?[]const u8 = null,
    base_url: ?[]const u8 = null,
    workspace_root: []const u8 = ".",
    has_agents_md: bool = false,

    pub fn load(allocator: std.mem.Allocator, io: std.Io, workspace_root: []const u8) AppConfig {
        var cfg = AppConfig{
            .workspace_root = workspace_root,
        };

        const cwd = std.Io.Dir.cwd();
        // Check for AGENTS.md
        if (cwd.openFile(io, "AGENTS.md", .{})) |f| {
            f.close(io);
            cfg.has_agents_md = true;
        } else |_| {}

        // Check environment variables
        if (std.process.Environ.createMap(.{ .block = .global }, allocator)) |env_map| {
            var mut_env = env_map;
            defer mut_env.deinit();

            if (mut_env.get("GEMINI_API_KEY")) |key| {
                cfg.provider_type = .gemini;
                cfg.model = "gemini-2.5-flash";
                cfg.api_key = key;
            } else if (mut_env.get("OPENAI_API_KEY")) |key| {
                cfg.provider_type = .openai;
                cfg.model = "gpt-4o";
                cfg.api_key = key;
            } else if (mut_env.get("ANTHROPIC_API_KEY")) |key| {
                cfg.provider_type = .anthropic;
                cfg.model = "claude-3-5-sonnet-20241022";
                cfg.api_key = key;
            }
        } else |_| {}

        return cfg;
    }
};

test "config loader" {
    const allocator = std.testing.allocator;
    var threaded = std.Io.Threaded.init(allocator, .{ .environ = .{ .block = .global } });
    defer threaded.deinit();
    const io = threaded.io();

    const cfg = AppConfig.load(allocator, io, ".");
    try std.testing.expect(cfg.workspace_root.len > 0);
}
