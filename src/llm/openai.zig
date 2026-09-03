const std = @import("std");
const prov = @import("provider.zig");
const transport = @import("http_transport.zig");
pub const CompletionRequest = prov.CompletionRequest;
pub const CompletionResponse = prov.CompletionResponse;
pub const ToolCall = prov.ToolCall;

pub const OpenAIProvider = struct {
    api_key: []const u8,
    base_url: []const u8 = "https://api.openai.com/v1",

    pub fn init(api_key: []const u8, base_url: ?[]const u8) OpenAIProvider {
        return .{
            .api_key = api_key,
            .base_url = base_url orelse "https://api.openai.com/v1",
        };
    }

    pub fn buildPayload(allocator: std.mem.Allocator, request: CompletionRequest) ![]u8 {
        var output: std.Io.Writer.Allocating = .init(allocator);
        errdefer output.deinit();
        const writer = &output.writer;

        try writer.writeAll("{\"model\":");
        try std.json.Stringify.value(request.model, .{}, writer);
        try writer.writeAll(",\"messages\":[");

        var message_count: usize = 0;
        if (request.system_prompt) |system_prompt| {
            try appendMessage(writer, &message_count, "system", system_prompt, null);
        }

        for (request.messages) |message| {
            try appendMessage(
                writer,
                &message_count,
                message.role.asString(),
                message.content,
                message.tool_call_id,
            );
        }

        try writer.writeAll("],\"temperature\":");
        try std.json.Stringify.value(request.temperature, .{}, writer);
        try writer.writeByte('}');

        return output.toOwnedSlice();
    }

    fn appendMessage(
        writer: *std.Io.Writer,
        message_count: *usize,
        role: []const u8,
        content: []const u8,
        tool_call_id: ?[]const u8,
    ) !void {
        if (message_count.* > 0) try writer.writeByte(',');
        message_count.* += 1;

        try writer.writeAll("{\"role\":");
        try std.json.Stringify.value(role, .{}, writer);
        try writer.writeAll(",\"content\":");
        try std.json.Stringify.value(content, .{}, writer);
        if (tool_call_id) |id| {
            try writer.writeAll(",\"tool_call_id\":");
            try std.json.Stringify.value(id, .{}, writer);
        }
        try writer.writeByte('}');
    }

    pub fn send(self: OpenAIProvider, allocator: std.mem.Allocator, io: std.Io, request: CompletionRequest) !CompletionResponse {
        if (self.api_key.len == 0) return error.MissingApiKey;

        const endpoint = try std.fmt.allocPrint(allocator, "{s}/chat/completions", .{self.base_url});
        defer allocator.free(endpoint);

        const payload = try buildPayload(allocator, request);
        defer allocator.free(payload);

        const authorization = try std.fmt.allocPrint(allocator, "Bearer {s}", .{self.api_key});
        defer allocator.free(authorization);

        const privileged_headers = [_]std.http.Header{
            .{ .name = "authorization", .value = authorization },
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

        const choices = parsed.value.object.get("choices") orelse return error.InvalidResponse;
        if (choices.array.items.len == 0) return error.EmptyChoices;

        const first_choice = choices.array.items[0];
        const message_obj = first_choice.object.get("message") orelse return error.InvalidResponse;
        const content_value = message_obj.object.get("content") orelse return error.InvalidResponse;
        const content = switch (content_value) {
            .string => |value| value,
            else => return error.InvalidResponse,
        };

        return .{
            .content = try allocator.dupe(u8, content),
            .tool_calls = null,
            .tokens_used = 150,
        };
    }
};

test "OpenAI payload includes system prompt and tool correlation id" {
    const allocator = std.testing.allocator;
    const messages = [_]prov.ChatMessage{
        .{ .role = .user, .content = "hello" },
        .{ .role = .tool, .content = "done", .tool_call_id = "call-1" },
    };

    const payload = try OpenAIProvider.buildPayload(allocator, .{
        .messages = &messages,
        .system_prompt = "system rules",
        .model = "gpt-test",
    });
    defer allocator.free(payload);

    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, payload, .{});
    defer parsed.deinit();

    const object = parsed.value.object;
    try std.testing.expectEqualStrings("gpt-test", object.get("model").?.string);
    const messages_json = object.get("messages").?.array.items;
    try std.testing.expectEqual(@as(usize, 3), messages_json.len);
    try std.testing.expectEqualStrings("system", messages_json[0].object.get("role").?.string);
    try std.testing.expectEqualStrings("call-1", messages_json[2].object.get("tool_call_id").?.string);
}

test "OpenAI provider rejects empty API key before network access" {
    const provider = OpenAIProvider.init("", null);
    try std.testing.expectError(error.MissingApiKey, provider.send(std.testing.allocator, std.testing.io, .{
        .messages = &.{},
        .model = "gpt-test",
    }));
}
