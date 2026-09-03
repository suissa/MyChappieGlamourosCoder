const std = @import("std");
const prov = @import("provider.zig");
const mock_mod = @import("mock.zig");
const gemini_mod = @import("gemini.zig");
const openai_mod = @import("openai.zig");
const anthropic_mod = @import("anthropic.zig");
const ollama_mod = @import("ollama.zig");

pub const Client = union(prov.ProviderType) {
    gemini: gemini_mod.GeminiProvider,
    openai: openai_mod.OpenAIProvider,
    anthropic: anthropic_mod.AnthropicProvider,
    ollama: ollama_mod.OllamaProvider,
    mock: mock_mod.MockProvider,

    pub fn init(provider_type: prov.ProviderType, api_key: ?[]const u8, base_url: ?[]const u8) !Client {
        return switch (provider_type) {
            .mock => .{ .mock = mock_mod.MockProvider.init() },
            .gemini => .{ .gemini = gemini_mod.GeminiProvider.init(api_key orelse return error.MissingApiKey) },
            .openai => .{ .openai = openai_mod.OpenAIProvider.init(api_key orelse return error.MissingApiKey, base_url) },
            .anthropic => .{ .anthropic = anthropic_mod.AnthropicProvider.init(api_key orelse return error.MissingApiKey) },
            .ollama => .{ .ollama = ollama_mod.OllamaProvider.init(base_url) },
        };
    }

    pub fn providerType(self: *const Client) prov.ProviderType {
        return std.meta.activeTag(self.*);
    }

    pub fn send(
        self: *Client,
        allocator: std.mem.Allocator,
        io: std.Io,
        request: prov.CompletionRequest,
    ) !prov.CompletionResponse {
        return switch (self.*) {
            .mock => |*provider| provider.send(allocator, io, request),
            .gemini => |*provider| provider.send(allocator, io, request),
            .openai => |*provider| provider.send(allocator, io, request),
            .anthropic => |*provider| provider.send(allocator, io, request),
            .ollama => |*provider| provider.send(allocator, io, request),
        };
    }
};

test "runtime LLM client selects deterministic mock" {
    var client = try Client.init(.mock, null, null);
    try std.testing.expectEqual(prov.ProviderType.mock, client.providerType());
}

test "cloud clients require credentials at construction" {
    try std.testing.expectError(error.MissingApiKey, Client.init(.openai, null, null));
    try std.testing.expectError(error.MissingApiKey, Client.init(.gemini, null, null));
    try std.testing.expectError(error.MissingApiKey, Client.init(.anthropic, null, null));
}
