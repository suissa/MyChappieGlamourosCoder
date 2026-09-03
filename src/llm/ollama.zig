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
        var output: std.Io.Writer.Allocating = .init(allocator);
        errdefer output.deinit();
        const writer = &output.writer;

        try writer.writeAll("{\"model\":");
        try std.json.Stringify.value(request.model, .{}, writer);
        try writer.writeAll(",\"stream\":false,\"messages\":[");

        var message_count: usize = 0;
        if (request.system_prompt) |system_prompt| {
            try appendMessage(writer, &message_count, "system", system_prompt);
        }
        for (request.messages) |message| {
            try appendMessage(writer, &message_count, message.role.asString(), message.content);
        }

        try writer.writeAll("],\"options\":{\"temperature\":");
        try std.json.Stringify.value(request.temperature, .{}, writer);
        try writer.writeAll("}}");

        return output.toOwnedSlice();
    }

    fn appendMessage(
        writer: *std.Io.Writer,
        message_count: *usize,
        role: []const u8,
        content: []const u8,
    ) !void {
        if (message_count.* > 0) try writer.writeByte(',');
        message_count.* += 1;

        try writer.writeAll("{\"role\":");
        try std.json.Stringify.value(role, .{}, writer);
        try writer.writeAll(",\"content\":");
        try std.json.Stringify.value(content, .{}, writer);
        try writer.writeByte('}');
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
