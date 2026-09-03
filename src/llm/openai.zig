const std = @import("std");
const prov = @import("provider.zig");
const http = @import("http.zig");
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

    pub fn send(self: OpenAIProvider, allocator: std.mem.Allocator, io: std.Io, request: CompletionRequest) !CompletionResponse {
        if (self.api_key.len == 0) return error.MissingApiKey;

        const endpoint = try std.fmt.allocPrint(allocator, "{s}/chat/completions", .{self.base_url});
        defer allocator.free(endpoint);

        const payload = try buildPayload(allocator, request);
        defer allocator.free(payload);

        const auth_header = try std.fmt.allocPrint(allocator, "Bearer {s}", .{self.api_key});
        defer allocator.free(auth_header);

        const body = try http.postJson(allocator, io, endpoint, payload, &.{
            .{ .name = "authorization", .value = auth_header },
        });
        defer allocator.free(body);

        return parseResponse(allocator, body);
    }
};

fn buildPayload(allocator: std.mem.Allocator, request: CompletionRequest) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(allocator);
    errdefer out.deinit();
    var jw: std.json.Stringify = .{ .writer = &out.writer };

    try jw.beginObject();
    try jw.objectField("model");
    try jw.write(request.model);

    try jw.objectField("messages");
    try jw.beginArray();

    if (request.system_prompt.len > 0) {
        try writeSimpleMessage(&jw, "system", request.system_prompt);
    }

    for (request.messages) |msg| {
        try jw.beginObject();
        try jw.objectField("role");
        try jw.write(msg.role.asString());

        try jw.objectField("content");
        try jw.write(msg.content);

        if (msg.tool_call_id) |tool_call_id| {
            try jw.objectField("tool_call_id");
            try jw.write(tool_call_id);
        }

        if (msg.tool_calls) |calls| {
            if (calls.len > 0) {
                try jw.objectField("tool_calls");
                try jw.beginArray();
                for (calls) |call| {
                    try jw.beginObject();
                    try jw.objectField("id");
                    try jw.write(call.id);
                    try jw.objectField("type");
                    try jw.write("function");
                    try jw.objectField("function");
                    try jw.beginObject();
                    try jw.objectField("name");
                    try jw.write(call.name);
                    try jw.objectField("arguments");
                    try jw.write(call.arguments_json);
                    try jw.endObject();
                    try jw.endObject();
                }
                try jw.endArray();
            }
        }

        try jw.endObject();
    }
    try jw.endArray();

    if (request.tools.len > 0) {
        try jw.objectField("tools");
        try jw.beginArray();
        for (request.tools) |tool| {
            var schema = try std.json.parseFromSlice(std.json.Value, allocator, tool.parameters_json, .{});
            defer schema.deinit();

            try jw.beginObject();
            try jw.objectField("type");
            try jw.write("function");
            try jw.objectField("function");
            try jw.beginObject();
            try jw.objectField("name");
            try jw.write(tool.name);
            try jw.objectField("description");
            try jw.write(tool.description);
            try jw.objectField("parameters");
            try jw.write(schema.value);
            try jw.endObject();
            try jw.endObject();
        }
        try jw.endArray();
    }

    try jw.endObject();
    return out.toOwnedSlice();
}

fn writeSimpleMessage(jw: *std.json.Stringify, role: []const u8, content: []const u8) !void {
    try jw.beginObject();
    try jw.objectField("role");
    try jw.write(role);
    try jw.objectField("content");
    try jw.write(content);
    try jw.endObject();
}

fn parseResponse(allocator: std.mem.Allocator, body: []const u8) !CompletionResponse {
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, body, .{});
    defer parsed.deinit();

    const root = asObject(parsed.value) orelse return error.InvalidResponse;
    const choices = asArray(root.get("choices") orelse return error.InvalidResponse) orelse return error.InvalidResponse;
    if (choices.items.len == 0) return error.EmptyChoices;

    const choice = asObject(choices.items[0]) orelse return error.InvalidResponse;
    const message = asObject(choice.get("message") orelse return error.InvalidResponse) orelse return error.InvalidResponse;

    var content: ?[]const u8 = null;
    if (message.get("content")) |content_value| {
        if (asString(content_value)) |text| content = try allocator.dupe(u8, text);
    }
    errdefer if (content) |text| allocator.free(text);

    var tool_calls: ?[]ToolCall = null;
    if (message.get("tool_calls")) |calls_value| {
        const calls_array = asArray(calls_value) orelse return error.InvalidResponse;
        if (calls_array.items.len > 0) {
            const calls = try allocator.alloc(ToolCall, calls_array.items.len);
            var initialized: usize = 0;
            errdefer {
                for (calls[0..initialized]) |*call| call.deinit(allocator);
                allocator.free(calls);
            }

            for (calls_array.items, 0..) |call_value, index| {
                const call_obj = asObject(call_value) orelse return error.InvalidResponse;
                const function_obj = asObject(call_obj.get("function") orelse return error.InvalidResponse) orelse return error.InvalidResponse;
                const id = asString(call_obj.get("id") orelse return error.InvalidResponse) orelse return error.InvalidResponse;
                const name = asString(function_obj.get("name") orelse return error.InvalidResponse) orelse return error.InvalidResponse;
                const arguments = asString(function_obj.get("arguments") orelse return error.InvalidResponse) orelse return error.InvalidResponse;

                calls[index] = .{
                    .id = try allocator.dupe(u8, id),
                    .name = try allocator.dupe(u8, name),
                    .arguments_json = try allocator.dupe(u8, arguments),
                };
                initialized += 1;
            }
            tool_calls = calls;
        }
    }

    const tokens_used = if (root.get("usage")) |usage_value| blk: {
        const usage = asObject(usage_value) orelse break :blk null;
        const total = usage.get("total_tokens") orelse break :blk null;
        break :blk asUsize(total);
    } else null;

    return .{
        .content = content,
        .tool_calls = tool_calls,
        .tokens_used = tokens_used,
    };
}

fn asObject(value: std.json.Value) ?std.json.ObjectMap {
    return switch (value) { .object => |object| object, else => null };
}

fn asArray(value: std.json.Value) ?std.json.Array {
    return switch (value) { .array => |array| array, else => null };
}

fn asString(value: std.json.Value) ?[]const u8 {
    return switch (value) { .string => |text| text, else => null };
}

fn asUsize(value: std.json.Value) ?usize {
    return switch (value) {
        .integer => |number| if (number >= 0) @intCast(number) else null,
        else => null,
    };
}

test "OpenAI response parser extracts tool calls" {
    const allocator = std.testing.allocator;
    const fixture =
        \\{"choices":[{"message":{"role":"assistant","content":null,"tool_calls":[{"id":"call_1","type":"function","function":{"name":"write","arguments":"{\\\"path\\\":\\\"x.txt\\\"}"}}]}}],"usage":{"total_tokens":42}}
    ;

    var response = try parseResponse(allocator, fixture);
    defer response.deinit(allocator);

    try std.testing.expect(response.tool_calls != null);
    try std.testing.expectEqualStrings("write", response.tool_calls.?[0].name);
    try std.testing.expectEqual(@as(?usize, 42), response.tokens_used);
}
