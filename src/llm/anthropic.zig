const std = @import("std");
const prov = @import("provider.zig");
const http = @import("http.zig");
pub const CompletionRequest = prov.CompletionRequest;
pub const CompletionResponse = prov.CompletionResponse;
pub const ToolCall = prov.ToolCall;

pub const AnthropicProvider = struct {
    api_key: []const u8,

    pub fn init(api_key: []const u8) AnthropicProvider {
        return .{ .api_key = api_key };
    }

    pub fn send(self: AnthropicProvider, allocator: std.mem.Allocator, io: std.Io, request: CompletionRequest) !CompletionResponse {
        if (self.api_key.len == 0) return error.MissingApiKey;

        const payload = try buildPayload(allocator, request);
        defer allocator.free(payload);

        const body = try http.postJson(
            allocator,
            io,
            "https://api.anthropic.com/v1/messages",
            payload,
            &.{
                .{ .name = "x-api-key", .value = self.api_key },
                .{ .name = "anthropic-version", .value = "2023-06-01" },
            },
        );
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
    try jw.objectField("max_tokens");
    try jw.write(@as(usize, 4096));

    if (request.system_prompt.len > 0) {
        try jw.objectField("system");
        try jw.write(request.system_prompt);
    }

    if (request.tools.len > 0) {
        try jw.objectField("tools");
        try jw.beginArray();
        for (request.tools) |tool| {
            var schema = try std.json.parseFromSlice(std.json.Value, allocator, tool.parameters_json, .{});
            defer schema.deinit();

            try jw.beginObject();
            try jw.objectField("name");
            try jw.write(tool.name);
            try jw.objectField("description");
            try jw.write(tool.description);
            try jw.objectField("input_schema");
            try jw.write(schema.value);
            try jw.endObject();
        }
        try jw.endArray();
    }

    try jw.objectField("messages");
    try jw.beginArray();

    var index: usize = 0;
    while (index < request.messages.len) {
        const msg = request.messages[index];
        switch (msg.role) {
            .system => {}, // Anthropic system content is top-level.
            .user => try writeTextMessage(&jw, "user", msg.content),
            .assistant => try writeAssistantMessage(allocator, &jw, msg),
            .tool => {
                // Anthropic expects client tool results as content blocks in a
                // user message. Consecutive tool results from parallel calls
                // are grouped into one user turn.
                try jw.beginObject();
                try jw.objectField("role");
                try jw.write("user");
                try jw.objectField("content");
                try jw.beginArray();
                while (index < request.messages.len and request.messages[index].role == .tool) : (index += 1) {
                    const tool_msg = request.messages[index];
                    try jw.beginObject();
                    try jw.objectField("type");
                    try jw.write("tool_result");
                    try jw.objectField("tool_use_id");
                    try jw.write(tool_msg.tool_call_id orelse return error.InvalidToolResult);
                    try jw.objectField("content");
                    try jw.write(tool_msg.content);
                    try jw.endObject();
                }
                try jw.endArray();
                try jw.endObject();
                continue;
            },
        }
        index += 1;
    }

    try jw.endArray();
    try jw.endObject();
    return out.toOwnedSlice();
}

fn writeTextMessage(jw: *std.json.Stringify, role: []const u8, content: []const u8) !void {
    try jw.beginObject();
    try jw.objectField("role");
    try jw.write(role);
    try jw.objectField("content");
    try jw.write(content);
    try jw.endObject();
}

fn writeAssistantMessage(allocator: std.mem.Allocator, jw: *std.json.Stringify, msg: prov.ChatMessage) !void {
    if (msg.tool_calls == null or msg.tool_calls.?.len == 0) {
        return writeTextMessage(jw, "assistant", msg.content);
    }

    try jw.beginObject();
    try jw.objectField("role");
    try jw.write("assistant");
    try jw.objectField("content");
    try jw.beginArray();

    if (msg.content.len > 0) {
        try jw.beginObject();
        try jw.objectField("type");
        try jw.write("text");
        try jw.objectField("text");
        try jw.write(msg.content);
        try jw.endObject();
    }

    for (msg.tool_calls.?) |call| {
        var input = try std.json.parseFromSlice(std.json.Value, allocator, call.arguments_json, .{});
        defer input.deinit();

        try jw.beginObject();
        try jw.objectField("type");
        try jw.write("tool_use");
        try jw.objectField("id");
        try jw.write(call.id);
        try jw.objectField("name");
        try jw.write(call.name);
        try jw.objectField("input");
        try jw.write(input.value);
        try jw.endObject();
    }

    try jw.endArray();
    try jw.endObject();
}

fn parseResponse(allocator: std.mem.Allocator, body: []const u8) !CompletionResponse {
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, body, .{});
    defer parsed.deinit();

    const root = asObject(parsed.value) orelse return error.InvalidResponse;
    const content_blocks = asArray(root.get("content") orelse return error.InvalidResponse) orelse return error.InvalidResponse;

    var text_out: std.Io.Writer.Allocating = .init(allocator);
    defer text_out.deinit();
    var call_count: usize = 0;

    for (content_blocks.items) |block_value| {
        const block = asObject(block_value) orelse continue;
        const block_type = asString(block.get("type") orelse continue) orelse continue;
        if (std.mem.eql(u8, block_type, "text")) {
            const text = asString(block.get("text") orelse continue) orelse continue;
            if (text_out.written().len > 0) try text_out.writer.writeAll("\n");
            try text_out.writer.writeAll(text);
        } else if (std.mem.eql(u8, block_type, "tool_use")) {
            call_count += 1;
        }
    }

    const content: ?[]const u8 = if (text_out.written().len > 0)
        try allocator.dupe(u8, text_out.written())
    else
        null;
    errdefer if (content) |text| allocator.free(text);

    var tool_calls: ?[]ToolCall = null;
    if (call_count > 0) {
        const calls = try allocator.alloc(ToolCall, call_count);
        var initialized: usize = 0;
        errdefer {
            for (calls[0..initialized]) |*call| call.deinit(allocator);
            allocator.free(calls);
        }

        for (content_blocks.items) |block_value| {
            const block = asObject(block_value) orelse continue;
            const block_type = asString(block.get("type") orelse continue) orelse continue;
            if (!std.mem.eql(u8, block_type, "tool_use")) continue;

            const id = asString(block.get("id") orelse return error.InvalidResponse) orelse return error.InvalidResponse;
            const name = asString(block.get("name") orelse return error.InvalidResponse) orelse return error.InvalidResponse;
            const input = block.get("input") orelse return error.InvalidResponse;
            const arguments_json = try stringifyValue(allocator, input);
            errdefer allocator.free(arguments_json);

            calls[initialized] = .{
                .id = try allocator.dupe(u8, id),
                .name = try allocator.dupe(u8, name),
                .arguments_json = arguments_json,
            };
            initialized += 1;
        }
        tool_calls = calls;
    }

    const tokens_used = if (root.get("usage")) |usage_value| blk: {
        const usage = asObject(usage_value) orelse break :blk null;
        const input_tokens = if (usage.get("input_tokens")) |value| asUsize(value) orelse 0 else 0;
        const output_tokens = if (usage.get("output_tokens")) |value| asUsize(value) orelse 0 else 0;
        break :blk if (input_tokens > 0 or output_tokens > 0) input_tokens + output_tokens else null;
    } else null;

    return .{ .content = content, .tool_calls = tool_calls, .tokens_used = tokens_used };
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

test "Anthropic response parser extracts text, tools and usage" {
    const allocator = std.testing.allocator;
    const fixture =
        \\{"content":[{"type":"text","text":"Vou verificar."},{"type":"tool_use","id":"toolu_1","name":"view","input":{"path":"README.md"}}],"usage":{"input_tokens":20,"output_tokens":7}}
    ;

    var response = try parseResponse(allocator, fixture);
    defer response.deinit(allocator);
    try std.testing.expectEqualStrings("Vou verificar.", response.content.?);
    try std.testing.expectEqualStrings("view", response.tool_calls.?[0].name);
    try std.testing.expectEqual(@as(?usize, 27), response.tokens_used);
}
