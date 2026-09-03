const std = @import("std");
const prov = @import("provider.zig");
const mock_mod = @import("mock.zig");
const gemini_mod = @import("gemini.zig");
const openai_mod = @import("openai.zig");
const anthropic_mod = @import("anthropic.zig");
const ollama_mod = @import("ollama.zig");

pub const RuntimeProvider = union(prov.ProviderType) {
    gemini: gemini_mod.GeminiProvider,
    openai: openai_mod.OpenAIProvider,
    anthropic: anthropic_mod.AnthropicProvider,
    ollama: ollama_mod.OllamaProvider,
    mock: mock_mod.MockProvider,

    pub fn init(
        provider_type: prov.ProviderType,
        api_key: ?[]const u8,
        base_url: ?[]const u8,
    ) !RuntimeProvider {
        return switch (provider_type) {
            .mock => .{ .mock = mock_mod.MockProvider.init() },
            .gemini => .{ .gemini = gemini_mod.GeminiProvider.init(api_key orelse return error.MissingApiKey) },
            .openai => .{ .openai = openai_mod.OpenAIProvider.init(api_key orelse return error.MissingApiKey, base_url) },
            .anthropic => .{ .anthropic = anthropic_mod.AnthropicProvider.init(api_key orelse return error.MissingApiKey) },
            .ollama => .{ .ollama = ollama_mod.OllamaProvider.init(base_url) },
        };
    }

    pub fn providerType(self: *const RuntimeProvider) prov.ProviderType {
        return switch (self.*) {
            .gemini => .gemini,
            .openai => .openai,
            .anthropic => .anthropic,
            .ollama => .ollama,
            .mock => .mock,
        };
    }

    pub fn send(
        self: *RuntimeProvider,
        allocator: std.mem.Allocator,
        io: std.Io,
        request: prov.CompletionRequest,
    ) !prov.CompletionResponse {
        return switch (self.*) {
            .mock => |*provider| provider.send(allocator, io, request),
            .gemini => |provider| provider.send(allocator, io, request),
            .openai => |provider| provider.send(allocator, io, request),
            .anthropic => |provider| provider.send(allocator, io, request),
            .ollama => |provider| provider.send(allocator, io, request),
        };
    }

    pub fn mockStepCount(self: *const RuntimeProvider) ?usize {
        return switch (self.*) {
            .mock => |provider| provider.step_count,
            else => null,
        };
    }
};

test "runtime provider defaults can instantiate mock without credentials" {
    var provider = try RuntimeProvider.init(.mock, null, null);
    try std.testing.expectEqual(prov.ProviderType.mock, provider.providerType());
    try std.testing.expectEqual(@as(?usize, 0), provider.mockStepCount());
}

test "runtime provider fails closed when a cloud credential is missing" {
    try std.testing.expectError(error.MissingApiKey, RuntimeProvider.init(.gemini, null, null));
    try std.testing.expectError(error.MissingApiKey, RuntimeProvider.init(.openai, null, null));
    try std.testing.expectError(error.MissingApiKey, RuntimeProvider.init(.anthropic, null, null));
}

test "runtime provider dispatches through mock implementation" {
    const allocator = std.testing.allocator;
    const messages = [_]prov.ChatMessage{
        .{ .role = .user, .content = "hello" },
    };

    var provider = try RuntimeProvider.init(.mock, null, null);
    var response = try provider.send(allocator, std.testing.io, .{
        .messages = &messages,
        .model = "mock-chappie-v1",
    });
    defer response.deinit(allocator);

    try std.testing.expect(response.content != null);
    try std.testing.expectEqual(@as(?usize, 1), provider.mockStepCount());
}

test "runtime provider maps base_url to Ollama host" {
    const host = "http://127.0.0.1:9999";
    const provider = try RuntimeProvider.init(.ollama, null, host);
    switch (provider) {
        .ollama => |ollama| try std.testing.expectEqualStrings(host, ollama.host),
        else => return error.UnexpectedProvider,
    }
}
