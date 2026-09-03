const std = @import("std");
const prov = @import("provider.zig");
const http = @import("http.zig");
pub const CompletionRequest = prov.CompletionRequest;
pub const CompletionResponse = prov.CompletionResponse;
pub const ToolCall = prov.ToolCall;

pub const OllamaProvider = struct {
    host: []const u8 = "http://127.0.0.1:11434",

    pub fn init(host: ?[]const u8) OllamaProvider {
        return .{ .host = host orelse "http://127.0.0.1:11434" };
    }

    pub fn send(self: OllamaProvider, allocator: std.mem.Allocator, io: std.Io, request: CompletionRequest) !CompletionResponse {
        const endpoint = try std.fmt.allocPrint(allocator, "{s}/api/chat", .{self.host});
        defer allocator.free(endpoint);

        const payload = try buildPayload(allocator, request);
        defer allocator.free(payload);

        const body = try http.postJson(allocator, io, endpoint, payload, &.{});
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
    try jw.objectField("stream");
    try jw.write(false);

    try jw.objectField("messages");
    try jw.beginArray();
    if (request.system_prompt.len > 0) try writeSimpleMessage(&jw, "system", request.system_prompt);

    for (request.messages, 0..) |msg, message_index| {
        try jw.beginObject();
        try jw.objectField("role");
        try jw.write(msg.role.asString());
        try jw.objectField("content");
        try jw.write(msg.content);

        if (msg.role == .tool) {
            if (msg.tool_call_id) |tool_call_id| {
                if (findToolName(request.messages, message_index, tool_call_id)) |tool_name| {
                    try jw.objectField("tool_name");
                    try jw.write(tool_name);
                }
            }
        }

        if (msg.tool_calls) |calls| {
            if (calls.len > 0) {
                try jw.objectField("tool_calls");
                try jw.beginArray();
                for (calls, 0..) |call, call_index| {
                    var args = try std.json.parseFromSlice(std.json.Value, allocator, call.arguments_json, .{});
                    defer args.deinit();

                    try jw.beginObject();
                    try jw.objectField("type");
                    try jw.write("function");
                    try jw.objectField("function");
                    try jw.beginObject();
                    try jw.objectField("index");
                    try jw.write(call_index);
                    try jw.objectField("name");
                    try jw.write(call.name);
                    try jw.objectField("arguments");
                    try jw.write(args.value);
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

fn findToolName(messages: []const prov.ChatMessage, before_index: usize, tool_call_id: []const u8) ?[]const u8 {
    var index = before_index;
    while (index > 0) {
        index -= 1;
        if (messages[index].tool_calls) |calls| {
            for (calls) |call| {
                if (std.mem.eql(u8, call.id, tool_call_id)) return call.name;
            }
        }
    }
    return null;
}

fn parseResponse(allocator: std.mem.Allocator, body: []const u8) !CompletionResponse {
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, body, .{});
    defer parsed.deinit();

    const root = asObject(parsed.value) orelse return error.InvalidResponse;
    const message = asObject(root.get("message") orelse return error.InvalidResponse) orelse return error.InvalidResponse;

    var content: ?[]const u8 = null;
    if (message.get("content")) |value| {
        if (asString(value)) |text| {
            if (text.len > 0) content = try allocator.dupe(u8, text);
        }
    }
    errdefer if (content) |text| allocator.free(text);

    var tool_calls: ?[]ToolCall = null;
    if (message.get("tool_calls")) |value| {
        const array = asArray(value) orelse return error.InvalidResponse;
        if (array.items.len > 0) {
            const calls = try allocator.alloc(ToolCall, array.items.len);
            var initialized: usize = 0;
            errdefer {
                for (calls[0..initialized]) |*call| call.deinit(allocator);
                allocator.free(calls);
            }

            for (array.items, 0..) |call_value, index| {
                const call_obj = asObject(call_value) orelse return error.InvalidResponse;
                const function_obj = asObject(call_obj.get("function") orelse return error.InvalidResponse) orelse return error.InvalidResponse;
                const name = asString(function_obj.get("name") orelse return error.InvalidResponse) orelse return error.InvalidResponse;
                const arguments = function_obj.get("arguments") orelse return error.InvalidResponse;
                const arguments_json = try stringifyValue(allocator, arguments);
                errdefer allocator.free(arguments_json);
                const id = try std.fmt.allocPrint(allocator, "ollama-call-{d}", .{index});
                errdefer allocator.free(id);

                calls[index] = .{
                    .id = id,
                    .name = try allocator.dupe(u8, name),
                    .arguments_json = arguments_json,
                };
                initialized += 1;
            }
            tool_calls = calls;
        }
    }

    const prompt_tokens = if (root.get("prompt_eval_count")) |value| asUsize(value) orelse 0 else 0;
    const completion_tokens = if (root.get("eval_count")) |value| asUsize(value) orelse 0 else 0;
    const total_tokens: ?usize = if (prompt_tokens > 0 or completion_tokens > 0) prompt_tokens + completion_tokens else null;

    return .{ .content = content, .tool_calls = tool_calls, .tokens_used = total_tokens };
}

fn stringifyValue(allocator: std.mem.Allocator, value: std.json.Value) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(allocator);
    errdefer out.deinit();
    var jw: std.json.Stringify = .{ .writer = &out.writer };
    try jw.write(value);
    return out.toOwnedSlice();
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
    return switch (value) { .integer => |number| if (number >= 0) @intCast(number) else null, else => null };
}

test "Ollama response parser extracts function calls" {
    const allocator = std.testing.allocator;
    const fixture =
        \\{"message":{"role":"assistant","content":"","tool_calls":[{"type":"function","function":{"name":"view","arguments":{"path":"README.md"}}}]},"prompt_eval_count":10,"eval_count":5}
    ;

    var response = try parseResponse(allocator, fixture);
    defer response.deinit(allocator);
    try std.testing.expect(response.tool_calls != null);
    try std.testing.expectEqualStrings("view", response.tool_calls.?[0].name);
    try std.testing.expectEqual(@as(?usize, 15), response.tokens_used);
}
