const std = @import("std");
const prov = @import("llm/provider.zig");

pub const AppConfig = struct {
    provider_type: prov.ProviderType = .mock,
    model: []const u8 = "mock-chappie-v1",
    api_key: ?[]const u8 = null,
    base_url: ?[]const u8 = null,
    workspace_root: []const u8 = ".",
    has_agents_md: bool = false,

    pub fn load(
        io: std.Io,
        workspace_root: []const u8,
        environ_map: ?*const std.process.Environ.Map,
    ) AppConfig {
        var cfg = AppConfig{
            .workspace_root = workspace_root,
        };

        const cwd = std.Io.Dir.cwd();
        if (cwd.openFile(io, "AGENTS.md", .{})) |file| {
            file.close(io);
            cfg.has_agents_md = true;
        } else |_| {}

        // Zig 0.16 makes the process environment explicit. Production callers
        // inject init.environ_map; tests and embedded users may omit it.
        if (environ_map) |env| {
            if (env.get("GEMINI_API_KEY")) |key| {
                cfg.provider_type = .gemini;
                cfg.model = "gemini-2.5-flash";
                cfg.api_key = key;
            } else if (env.get("OPENAI_API_KEY")) |key| {
                cfg.provider_type = .openai;
                cfg.model = "gpt-4o";
                cfg.api_key = key;
                cfg.base_url = env.get("OPENAI_BASE_URL");
            } else if (env.get("ANTHROPIC_API_KEY")) |key| {
                cfg.provider_type = .anthropic;
                cfg.model = "claude-3-5-sonnet-20241022";
                cfg.api_key = key;
            } else if (env.get("OLLAMA_HOST")) |host| {
                cfg.provider_type = .ollama;
                cfg.model = env.get("OLLAMA_MODEL") orelse "qwen2.5-coder:7b";
                cfg.base_url = host;
            }

            // One provider-neutral override makes model selection declarative
            // without changing source code.
            if (env.get("MYCHAPPIE_MODEL")) |model| {
                cfg.model = model;
            }
        }

        return cfg;
    }
};

test "config loader without process environment" {
    const cfg = AppConfig.load(std.testing.io, ".", null);
    try std.testing.expect(cfg.workspace_root.len > 0);
    try std.testing.expectEqual(prov.ProviderType.mock, cfg.provider_type);
    try std.testing.expectEqualStrings("mock-chappie-v1", cfg.model);
}
