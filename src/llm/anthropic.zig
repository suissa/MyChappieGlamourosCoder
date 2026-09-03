const std = @import("std");
const prov = @import("provider.zig");
const transport = @import("http_transport.zig");
pub const CompletionRequest = prov.CompletionRequest;
pub const CompletionResponse = prov.CompletionResponse;
pub const ToolCall = prov.ToolCall;

pub const anthropic_version = "2023-06-01";

pub const AnthropicProvider = struct {
    api_key: []const u8,

    pub fn init(api_key: []const u8) AnthropicProvider {
        return .{ .api_key = api_key };
    }

    pub fn buildPayload(allocator: std.mem.Allocator, request: CompletionRequest) ![]u8 {
        var payload: std.ArrayList(u8) = .empty;
        errdefer payload.deinit(allocator);

        try payload.appendSlice(allocator, "{\"model\":");
        try std.json.stringify(request.model, .{}, payload.writer(allocator));
        try payload.appendSlice(allocator, ",\"max_tokens\":4096");

        if (request.system_prompt) |system_prompt| {
            try payload.appendSlice(allocator, ",\"system\":");
            try std.json.stringify(system_prompt, .{}, payload.writer(allocator));
        }

        try payload.appendSlice(allocator, ",\"temperature\":");
        try std.json.stringify(request.temperature, .{}, payload.writer(allocator));
        try payload.appendSlice(allocator, ",\"messages\":[");

        var message_count: usize = 0;
        for (request.messages) |message| {
            if (message.role == .system) continue;
            if (message_count > 0) try payload.appendSlice(allocator, ",");
            message_count += 1;

            const role = switch (message.role) {
                .assistant => "assistant",
                .user, .tool => "user",
                .system => unreachable,
            };
            try payload.appendSlice(allocator, "{\"role\":");
            try std.json.stringify(role, .{}, payload.writer(allocator));
            try payload.appendSlice(allocator, ",\"content\":");
            try std.json.stringify(message.content, .{}, payload.writer(allocator));
            try payload.appendSlice(allocator, "}");
        }

        try payload.appendSlice(allocator, "]}");
        return payload.toOwnedSlice(allocator);
    }

    pub fn send(self: AnthropicProvider, allocator: std.mem.Allocator, io: std.Io, request: CompletionRequest) !CompletionResponse {
        if (self.api_key.len == 0) return error.MissingApiKey;

        const payload = try buildPayload(allocator, request);
        defer allocator.free(payload);

        const extra_headers = [_]std.http.Header{
            .{ .name = "anthropic-version", .value = anthropic_version },
        };
        const privileged_headers = [_]std.http.Header{
            .{ .name = "x-api-key", .value = self.api_key },
        };

        var http_response = try transport.postJson(
            allocator,
            io,
            "https://api.anthropic.com/v1/messages",
            payload,
            &extra_headers,
            &privileged_headers,
        );
        defer http_response.deinit(allocator);

        if (http_response.status != .ok) return error.HttpError;

        var parsed = try std.json.parseFromSlice(std.json.Value, allocator, http_response.body, .{});
        defer parsed.deinit();

        const content_array = parsed.value.object.get("content") orelse return error.InvalidResponse;
        if (content_array.array.items.len == 0) return error.EmptyContent;

        var text: std.ArrayList(u8) = .empty;
        errdefer text.deinit(allocator);
        for (content_array.array.items) |block| {
            const text_value = block.object.get("text") orelse continue;
            switch (text_value) {
                .string => |value| try text.appendSlice(allocator, value),
                else => {},
            }
        }
        if (text.items.len == 0) return error.InvalidResponse;

        var tokens_used: ?usize = null;
        if (parsed.value.object.get("usage")) |usage| {
            const input_tokens = jsonInteger(usage.object.get("input_tokens"));
            const output_tokens = jsonInteger(usage.object.get("output_tokens"));
            if (input_tokens != null or output_tokens != null) {
                tokens_used = (input_tokens orelse 0) + (output_tokens orelse 0);
            }
        }

        return .{
            .content = try text.toOwnedSlice(allocator),
            .tool_calls = null,
            .tokens_used = tokens_used,
        };
    }
};

fn jsonInteger(value: ?std.json.Value) ?usize {
    const actual = value orelse return null;
    return switch (actual) {
        .integer => |number| if (number >= 0) @intCast(number) else null,
        else => null,
    };
}

test "Anthropic payload carries system prompt at top level" {
    const allocator = std.testing.allocator;
    const messages = [_]prov.ChatMessage{
        .{ .role = .system, .content = "legacy system message is skipped" },
        .{ .role = .user, .content = "hello" },
        .{ .role = .assistant, .content = "hi" },
    };

    const payload = try AnthropicProvider.buildPayload(allocator, .{
        .messages = &messages,
        .system_prompt = "system rules",
        .model = "claude-test",
    });
    defer allocator.free(payload);

    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, payload, .{});
    defer parsed.deinit();

    const object = parsed.value.object;
    try std.testing.expectEqualStrings("system rules", object.get("system").?.string);
    const messages_json = object.get("messages").?.array.items;
    try std.testing.expectEqual(@as(usize, 2), messages_json.len);
    try std.testing.expectEqualStrings("user", messages_json[0].object.get("role").?.string);
    try std.testing.expectEqualStrings("assistant", messages_json[1].object.get("role").?.string);
}

test "Anthropic provider rejects empty API key before network access" {
    const provider = AnthropicProvider.init("");
    try std.testing.expectError(error.MissingApiKey, provider.send(std.testing.allocator, std.testing.io, .{
        .messages = &.{},
        .model = "claude-test",
    }));
}

test "Anthropic API version is pinned" {
    try std.testing.expectEqualStrings("2023-06-01", anthropic_version);
}
