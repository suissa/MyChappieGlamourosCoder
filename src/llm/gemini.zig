const std = @import("std");
const prov = @import("provider.zig");
const transport = @import("http_transport.zig");
pub const CompletionRequest = prov.CompletionRequest;
pub const CompletionResponse = prov.CompletionResponse;
pub const ToolCall = prov.ToolCall;

pub const GeminiProvider = struct {
    api_key: []const u8,

    pub fn init(api_key: []const u8) GeminiProvider {
        return .{ .api_key = api_key };
    }

    pub fn buildPayload(allocator: std.mem.Allocator, request: CompletionRequest) ![]u8 {
        var output: std.Io.Writer.Allocating = .init(allocator);
        errdefer output.deinit();
        const writer = &output.writer;

        try writer.writeByte('{');
        if (request.system_prompt) |system_prompt| {
            try writer.writeAll("\"systemInstruction\":{\"parts\":[{\"text\":");
            try std.json.Stringify.value(system_prompt, .{}, writer);
            try writer.writeAll("}]},");
        }

        try writer.writeAll("\"contents\":[");
        for (request.messages, 0..) |message, index| {
            if (index > 0) try writer.writeByte(',');
            const role = switch (message.role) {
                .assistant => "model",
                .user, .system, .tool => "user",
            };
            try writer.writeAll("{\"role\":");
            try std.json.Stringify.value(role, .{}, writer);
            try writer.writeAll(",\"parts\":[{\"text\":");
            try std.json.Stringify.value(message.content, .{}, writer);
            try writer.writeAll("}]}");
        }
        try writer.writeAll("],\"generationConfig\":{\"temperature\":");
        try std.json.Stringify.value(request.temperature, .{}, writer);
        try writer.writeAll("}}");

        return output.toOwnedSlice();
    }

    pub fn send(self: GeminiProvider, allocator: std.mem.Allocator, io: std.Io, request: CompletionRequest) !CompletionResponse {
        if (self.api_key.len == 0) return error.MissingApiKey;

        const endpoint = try std.fmt.allocPrint(
            allocator,
            "https://generativelanguage.googleapis.com/v1beta/models/{s}:generateContent",
            .{request.model},
        );
        defer allocator.free(endpoint);

        const payload = try buildPayload(allocator, request);
        defer allocator.free(payload);

        // Google recommends x-goog-api-key for REST calls. Keeping the key out
        // of the URL prevents it from appearing in endpoint logs and traces.
        const privileged_headers = [_]std.http.Header{
            .{ .name = "x-goog-api-key", .value = self.api_key },
        };

        var http_response = try transport.postJson(
            allocator,
            io,
            endpoint,
            payload,
            &.{},
            &privileged_headers,
        );
        defer http_response.deinit(allocator);

        if (http_response.status != .ok) return error.HttpError;

        var parsed = try std.json.parseFromSlice(std.json.Value, allocator, http_response.body, .{});
        defer parsed.deinit();

        const candidates = parsed.value.object.get("candidates") orelse return error.InvalidResponse;
        if (candidates.array.items.len == 0) return error.EmptyCandidates;

        const first_candidate = candidates.array.items[0];
        const content_obj = first_candidate.object.get("content") orelse return error.InvalidResponse;
        const parts = content_obj.object.get("parts") orelse return error.InvalidResponse;

        var text: std.ArrayList(u8) = .empty;
        errdefer text.deinit(allocator);

        for (parts.array.items) |part| {
            if (part.object.get("text")) |value| {
                switch (value) {
                    .string => |string_value| try text.appendSlice(allocator, string_value),
                    else => {},
                }
            }
        }

        if (text.items.len == 0) return error.InvalidResponse;

        return .{
            .content = try text.toOwnedSlice(allocator),
            .tool_calls = null,
            .tokens_used = 100,
        };
    }
};

test "Gemini payload uses systemInstruction and Gemini roles" {
    const allocator = std.testing.allocator;
    const messages = [_]prov.ChatMessage{
        .{ .role = .user, .content = "hello" },
        .{ .role = .assistant, .content = "hi" },
    };

    const payload = try GeminiProvider.buildPayload(allocator, .{
        .messages = &messages,
        .system_prompt = "system rules",
        .model = "gemini-test",
    });
    defer allocator.free(payload);

    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, payload, .{});
    defer parsed.deinit();

    const object = parsed.value.object;
    try std.testing.expectEqualStrings(
        "system rules",
        object.get("systemInstruction").?.object.get("parts").?.array.items[0].object.get("text").?.string,
    );
    const contents = object.get("contents").?.array.items;
    try std.testing.expectEqualStrings("user", contents[0].object.get("role").?.string);
    try std.testing.expectEqualStrings("model", contents[1].object.get("role").?.string);
}

test "Gemini provider rejects empty API key before network access" {
    const provider = GeminiProvider.init("");
    try std.testing.expectError(error.MissingApiKey, provider.send(std.testing.allocator, std.testing.io, .{
        .messages = &.{},
        .model = "gemini-test",
    }));
}
