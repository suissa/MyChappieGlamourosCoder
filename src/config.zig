const std = @import("std");
const prov = @import("llm/provider.zig");

pub const AppConfig = struct {
    provider_type: prov.ProviderType = .mock,
    model: []const u8 = "mock-chappie-v1",
    api_key: ?[]const u8 = null,
    base_url: ?[]const u8 = null,
    workspace_root: []const u8 = ".",
    has_agents_md: bool = false,
    max_steps: usize = 10,
    dangerously_skip_permissions: bool = false,

    pub fn load(
        io: std.Io,
        workspace_root: []const u8,
        environ_map: ?*const std.process.Environ.Map,
    ) AppConfig {
        var cfg = AppConfig{
            .workspace_root = workspace_root,
        };

        const cwd = std.Io.Dir.cwd();
        if (cwd.openFile(io, "AGENTS.md", .{})) |f| {
            f.close(io);
            cfg.has_agents_md = true;
        } else |_| {}

        const env = environ_map orelse return cfg;

        // Prefer an explicit provider selection. When absent, preserve the
        // convenient credential-based discovery used by the first Zig port.
        if (env.get("MYCHAPPIE_PROVIDER")) |provider_name| {
            if (parseProviderType(provider_name)) |provider_type| {
                cfg.provider_type = provider_type;
                cfg.model = defaultModel(provider_type);
            }
        } else if (env.get("GEMINI_API_KEY")) |_| {
            cfg.provider_type = .gemini;
            cfg.model = defaultModel(.gemini);
        } else if (env.get("OPENAI_API_KEY")) |_| {
            cfg.provider_type = .openai;
            cfg.model = defaultModel(.openai);
        } else if (env.get("ANTHROPIC_API_KEY")) |_| {
            cfg.provider_type = .anthropic;
            cfg.model = defaultModel(.anthropic);
        } else if (env.get("OLLAMA_HOST")) |_| {
            cfg.provider_type = .ollama;
            cfg.model = defaultModel(.ollama);
        }

        cfg.api_key = switch (cfg.provider_type) {
            .gemini => env.get("GEMINI_API_KEY"),
            .openai => env.get("OPENAI_API_KEY"),
            .anthropic => env.get("ANTHROPIC_API_KEY"),
            .ollama, .mock => null,
        };

        cfg.base_url = env.get("MYCHAPPIE_BASE_URL") orelse switch (cfg.provider_type) {
            .openai => env.get("OPENAI_BASE_URL"),
            .ollama => env.get("OLLAMA_HOST"),
            else => null,
        };

        if (env.get("MYCHAPPIE_MODEL")) |model| {
            if (model.len > 0) cfg.model = model;
        }

        if (env.get("MYCHAPPIE_MAX_STEPS")) |raw_max_steps| {
            cfg.max_steps = std.fmt.parseInt(usize, raw_max_steps, 10) catch cfg.max_steps;
            if (cfg.max_steps == 0) cfg.max_steps = 1;
        }

        if (env.get("MYCHAPPIE_DANGEROUSLY_SKIP_PERMISSIONS")) |value| {
            cfg.dangerously_skip_permissions = isTruthy(value);
        }

        return cfg;
    }
};

pub fn parseProviderType(value: []const u8) ?prov.ProviderType {
    if (std.ascii.eqlIgnoreCase(value, "mock")) return .mock;
    if (std.ascii.eqlIgnoreCase(value, "gemini")) return .gemini;
    if (std.ascii.eqlIgnoreCase(value, "openai")) return .openai;
    if (std.ascii.eqlIgnoreCase(value, "anthropic") or std.ascii.eqlIgnoreCase(value, "claude")) return .anthropic;
    if (std.ascii.eqlIgnoreCase(value, "ollama")) return .ollama;
    return null;
}

fn defaultModel(provider_type: prov.ProviderType) []const u8 {
    return switch (provider_type) {
        .mock => "mock-chappie-v1",
        .gemini => "gemini-2.5-flash",
        .openai => "gpt-4o",
        .anthropic => "claude-3-5-sonnet-20241022",
        .ollama => "qwen2.5-coder:7b",
    };
}

fn isTruthy(value: []const u8) bool {
    return std.ascii.eqlIgnoreCase(value, "1") or
        std.ascii.eqlIgnoreCase(value, "true") or
        std.ascii.eqlIgnoreCase(value, "yes") or
        std.ascii.eqlIgnoreCase(value, "on");
}

test "config loader without process environment" {
    const cfg = AppConfig.load(std.testing.io, ".", null);
    try std.testing.expect(cfg.workspace_root.len > 0);
    try std.testing.expectEqual(prov.ProviderType.mock, cfg.provider_type);
    try std.testing.expect(!cfg.dangerously_skip_permissions);
}

test "provider names are parsed without case sensitivity" {
    try std.testing.expectEqual(prov.ProviderType.openai, parseProviderType("OPENAI").?);
    try std.testing.expectEqual(prov.ProviderType.anthropic, parseProviderType("claude").?);
    try std.testing.expect(parseProviderType("unsupported") == null);
}
