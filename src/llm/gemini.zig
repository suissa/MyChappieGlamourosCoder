const std = @import("std");
const prov = @import("provider.zig");
const http = @import("http.zig");
pub const CompletionRequest = prov.CompletionRequest;
pub const CompletionResponse = prov.CompletionResponse;
pub const ToolCall = prov.ToolCall;

pub const GeminiProvider = struct {
    api_key: []const u8,

    pub fn init(api_key: []const u8) GeminiProvider {
        return .{ .api_key = api_key };
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

        const body = try http.postJson(allocator, io, endpoint, payload, &.{
            .{ .name = "x-goog-api-key", .value = self.api_key },
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

    if (request.system_prompt.len > 0) {
        try jw.objectField("systemInstruction");
        try jw.beginObject();
        try jw.objectField("parts");
        try jw.beginArray();
        try jw.beginObject();
        try jw.objectField("text");
        try jw.write(request.system_prompt);
        try jw.endObject();
        try jw.endArray();
        try jw.endObject();
    }

    if (request.tools.len > 0) {
        try jw.objectField("tools");
        try jw.beginArray();
        try jw.beginObject();
        try jw.objectField("functionDeclarations");
        try jw.beginArray();
        for (request.tools) |tool| {
            var schema = try std.json.parseFromSlice(std.json.Value, allocator, tool.parameters_json, .{});
            defer schema.deinit();

            try jw.beginObject();
            try jw.objectField("name");
            try jw.write(tool.name);
            try jw.objectField("description");
            try jw.write(tool.description);
            try jw.objectField("parameters");
            try jw.write(schema.value);
            try jw.endObject();
        }
        try jw.endArray();
        try jw.endObject();
        try jw.endArray();
    }

    try jw.objectField("contents");
    try jw.beginArray();

    var index: usize = 0;
    while (index < request.messages.len) {
        const msg = request.messages[index];
        switch (msg.role) {
            .system => {},
            .user => try writeTextContent(&jw, "user", msg.content),
            .assistant => try writeModelContent(allocator, &jw, msg),
            .tool => {
                try jw.beginObject();
                try jw.objectField("role");
                try jw.write("user");
                try jw.objectField("parts");
                try jw.beginArray();

                while (index < request.messages.len and request.messages[index].role == .tool) : (index += 1) {
                    const tool_msg = request.messages[index];
                    const tool_call_id = tool_msg.tool_call_id orelse return error.InvalidToolResult;
                    const tool_name = findToolName(request.messages, index, tool_call_id) orelse return error.InvalidToolResult;

                    try jw.beginObject();
                    try jw.objectField("functionResponse");
                    try jw.beginObject();
                    try jw.objectField("id");
                    try jw.write(tool_call_id);
                    try jw.objectField("name");
                    try jw.write(tool_name);
                    try jw.objectField("response");
                    try jw.beginObject();
                    try jw.objectField("result");
                    try jw.write(tool_msg.content);
                    try jw.endObject();
                    try jw.endObject();
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

fn writeTextContent(jw: *std.json.Stringify, role: []const u8, text: []const u8) !void {
    try jw.beginObject();
    try jw.objectField("role");
    try jw.write(role);
    try jw.objectField("parts");
    try jw.beginArray();
    try jw.beginObject();
    try jw.objectField("text");
    try jw.write(text);
    try jw.endObject();
    try jw.endArray();
    try jw.endObject();
}

fn writeModelContent(allocator: std.mem.Allocator, jw: *std.json.Stringify, msg: prov.ChatMessage) !void {
    try jw.beginObject();
    try jw.objectField("role");
    try jw.write("model");
    try jw.objectField("parts");
    try jw.beginArray();

    if (msg.content.len > 0) {
        try jw.beginObject();
        try jw.objectField("text");
        try jw.write(msg.content);
        try jw.endObject();
    }

    if (msg.tool_calls) |calls| {
        for (calls) |call| {
            var args = try std.json.parseFromSlice(std.json.Value, allocator, call.arguments_json, .{});
            defer args.deinit();

            try jw.beginObject();
            try jw.objectField("functionCall");
            try jw.beginObject();
            try jw.objectField("id");
            try jw.write(call.id);
            try jw.objectField("name");
            try jw.write(call.name);
            try jw.objectField("args");
            try jw.write(args.value);
            try jw.endObject();
            try jw.endObject();
        }
    }

    try jw.endArray();
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
    const candidates = asArray(root.get("candidates") orelse return error.InvalidResponse) orelse return error.InvalidResponse;
    if (candidates.items.len == 0) return error.EmptyCandidates;

    const first_candidate = asObject(candidates.items[0]) orelse return error.InvalidResponse;
    const content = asObject(first_candidate.get("content") orelse return error.InvalidResponse) orelse return error.InvalidResponse;
    const parts = asArray(content.get("parts") orelse return error.InvalidResponse) orelse return error.InvalidResponse;

    var text_out: std.Io.Writer.Allocating = .init(allocator);
    defer text_out.deinit();
    var call_count: usize = 0;

    for (parts.items) |part_value| {
        const part = asObject(part_value) orelse continue;
        if (part.get("text")) |text_value| {
            if (asString(text_value)) |text| try text_out.writer.writeAll(text);
        }
        if (part.get("functionCall") != null) call_count += 1;
    }

    const response_text: ?[]const u8 = if (text_out.written().len > 0)
        try allocator.dupe(u8, text_out.written())
    else
        null;
    errdefer if (response_text) |text| allocator.free(text);

    var tool_calls: ?[]ToolCall = null;
    if (call_count > 0) {
        const calls = try allocator.alloc(ToolCall, call_count);
        var initialized: usize = 0;
        errdefer {
            for (calls[0..initialized]) |*call| call.deinit(allocator);
            allocator.free(calls);
        }

        for (parts.items) |part_value| {
            const part = asObject(part_value) orelse continue;
            const function_value = part.get("functionCall") orelse continue;
            const function = asObject(function_value) orelse return error.InvalidResponse;
            const name = asString(function.get("name") orelse return error.InvalidResponse) orelse return error.InvalidResponse;
            const args = function.get("args") orelse .{ .object = .empty };
            const arguments_json = try stringifyValue(allocator, args);
            errdefer allocator.free(arguments_json);

            const id = if (function.get("id")) |id_value|
                if (asString(id_value)) |api_id| try allocator.dupe(u8, api_id) else try std.fmt.allocPrint(allocator, "gemini-call-{d}", .{initialized})
            else
                try std.fmt.allocPrint(allocator, "gemini-call-{d}", .{initialized});
            errdefer allocator.free(id);

            calls[initialized] = .{
                .id = id,
                .name = try allocator.dupe(u8, name),
                .arguments_json = arguments_json,
            };
            initialized += 1;
        }
        tool_calls = calls;
    }

    const tokens_used = if (root.get("usageMetadata")) |usage_value| blk: {
        const usage = asObject(usage_value) orelse break :blk null;
        if (usage.get("totalTokenCount")) |total| break :blk asUsize(total);
        const prompt = if (usage.get("promptTokenCount")) |value| asUsize(value) orelse 0 else 0;
        const candidates_count = if (usage.get("candidatesTokenCount")) |value| asUsize(value) orelse 0 else 0;
        break :blk if (prompt > 0 or candidates_count > 0) prompt + candidates_count else null;
    } else null;

    return .{ .content = response_text, .tool_calls = tool_calls, .tokens_used = tokens_used };
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

test "Gemini response parser extracts text and function calls" {
    const allocator = std.testing.allocator;
    const fixture =
        \\{"candidates":[{"content":{"role":"model","parts":[{"text":"Vou ler."},{"functionCall":{"id":"fc_1","name":"view","args":{"path":"README.md"}}}]}}],"usageMetadata":{"totalTokenCount":31}}
    ;

    var response = try parseResponse(allocator, fixture);
    defer response.deinit(allocator);
    try std.testing.expectEqualStrings("Vou ler.", response.content.?);
    try std.testing.expectEqualStrings("view", response.tool_calls.?[0].name);
    try std.testing.expectEqual(@as(?usize, 31), response.tokens_used);
}
