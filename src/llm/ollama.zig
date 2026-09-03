const std = @import("std");
const prov = @import("provider.zig");
const transport = @import("http_transport.zig");
pub const CompletionRequest = prov.CompletionRequest;
pub const CompletionResponse = prov.CompletionResponse;
pub const ToolCall = prov.ToolCall;

pub const OllamaProvider = struct {
    host: []const u8 = "http://127.0.0.1:11434",

    pub fn init(host: ?[]const u8) OllamaProvider {
        return .{
            .host = host orelse "http://127.0.0.1:11434",
        };
    }

    pub fn buildPayload(allocator: std.mem.Allocator, request: CompletionRequest) ![]u8 {
        var payload: std.ArrayList(u8) = .empty;
        errdefer payload.deinit(allocator);

        try payload.appendSlice(allocator, "{\"model\":");
        try std.json.stringify(request.model, .{}, payload.writer(allocator));
        try payload.appendSlice(allocator, ",\"stream\":false,\"messages\":[");

        var message_count: usize = 0;
        if (request.system_prompt) |system_prompt| {
            try appendMessage(allocator, &payload, &message_count, "system", system_prompt);
        }
        for (request.messages) |message| {
            try appendMessage(allocator, &payload, &message_count, message.role.asString(), message.content);
        }

        try payload.appendSlice(allocator, "],\"options\":{\"temperature\":");
        try std.json.stringify(request.temperature, .{}, payload.writer(allocator));
        try payload.appendSlice(allocator, "}}");

        return payload.toOwnedSlice(allocator);
    }

    fn appendMessage(
        allocator: std.mem.Allocator,
        payload: *std.ArrayList(u8),
        message_count: *usize,
        role: []const u8,
        content: []const u8,
    ) !void {
        if (message_count.* > 0) try payload.appendSlice(allocator, ",");
        message_count.* += 1;

        try payload.appendSlice(allocator, "{\"role\":");
        try std.json.stringify(role, .{}, payload.writer(allocator));
        try payload.appendSlice(allocator, ",\"content\":");
        try std.json.stringify(content, .{}, payload.writer(allocator));
        try payload.appendSlice(allocator, "}");
    }

    pub fn send(self: OllamaProvider, allocator: std.mem.Allocator, io: std.Io, request: CompletionRequest) !CompletionResponse {
        const endpoint = try std.fmt.allocPrint(allocator, "{s}/api/chat", .{self.host});
        defer allocator.free(endpoint);

        const payload = try buildPayload(allocator, request);
        defer allocator.free(payload);

        var http_response = try transport.postJson(
            allocator,
            io,
            endpoint,
            payload,
            &.{},
            &.{},
        );
        defer http_response.deinit(allocator);

        if (http_response.status != .ok) return error.HttpError;

        var parsed = try std.json.parseFromSlice(std.json.Value, allocator, http_response.body, .{});
        defer parsed.deinit();

        const message_obj = parsed.value.object.get("message") orelse return error.InvalidResponse;
        const content_value = message_obj.object.get("content") orelse return error.InvalidResponse;
        const content = switch (content_value) {
            .string => |value| value,
            else => return error.InvalidResponse,
        };

        const prompt_tokens = jsonInteger(parsed.value.object.get("prompt_eval_count"));
        const output_tokens = jsonInteger(parsed.value.object.get("eval_count"));
        const tokens_used: ?usize = if (prompt_tokens != null or output_tokens != null)
            (prompt_tokens orelse 0) + (output_tokens orelse 0)
        else
            null;

        return .{
            .content = try allocator.dupe(u8, content),
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

test "Ollama payload includes explicit system message and disables streaming" {
    const allocator = std.testing.allocator;
    const messages = [_]prov.ChatMessage{
        .{ .role = .user, .content = "hello" },
    };

    const payload = try OllamaProvider.buildPayload(allocator, .{
        .messages = &messages,
        .system_prompt = "system rules",
        .model = "qwen-test",
    });
    defer allocator.free(payload);

    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, payload, .{});
    defer parsed.deinit();

    const object = parsed.value.object;
    try std.testing.expect(!object.get("stream").?.bool);
    const messages_json = object.get("messages").?.array.items;
    try std.testing.expectEqual(@as(usize, 2), messages_json.len);
    try std.testing.expectEqualStrings("system", messages_json[0].object.get("role").?.string);
    try std.testing.expectEqualStrings("system rules", messages_json[0].object.get("content").?.string);
}
