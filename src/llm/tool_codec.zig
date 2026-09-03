const std = @import("std");
const prov = @import("provider.zig");

pub fn jsonValueToOwnedSlice(allocator: std.mem.Allocator, value: std.json.Value) ![]u8 {
    var output: std.Io.Writer.Allocating = .init(allocator);
    errdefer output.deinit();
    try std.json.Stringify.value(value, .{}, &output.writer);
    return output.toOwnedSlice();
}

pub fn validateSchema(allocator: std.mem.Allocator, schema_json: []const u8) !void {
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, schema_json, .{});
    defer parsed.deinit();
    switch (parsed.value) {
        .object => {},
        else => return error.ToolSchemaMustBeObject,
    }
}

pub fn findToolNameByCallId(messages: []const prov.ChatMessage, call_id: []const u8) ?[]const u8 {
    var index = messages.len;
    while (index > 0) {
        index -= 1;
        const message = messages[index];
        const calls = message.tool_calls orelse continue;
        for (calls) |call| {
            if (std.mem.eql(u8, call.id, call_id)) return call.name;
        }
    }
    return null;
}

pub fn syntheticCallId(
    allocator: std.mem.Allocator,
    provider_name: []const u8,
    index: usize,
) ![]u8 {
    return std.fmt.allocPrint(allocator, "{s}-tool-call-{d}", .{ provider_name, index });
}

test "JSON values round-trip to owned argument JSON" {
    const allocator = std.testing.allocator;
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, "{\"path\":\"demo.txt\",\"count\":2}", .{});
    defer parsed.deinit();

    const encoded = try jsonValueToOwnedSlice(allocator, parsed.value);
    defer allocator.free(encoded);

    var reparsed = try std.json.parseFromSlice(std.json.Value, allocator, encoded, .{});
    defer reparsed.deinit();
    try std.testing.expectEqualStrings("demo.txt", reparsed.value.object.get("path").?.string);
}

test "tool call name resolves backwards from correlation id" {
    const calls = [_]prov.ToolCall{
        .{ .id = "call-123", .name = "write", .arguments_json = "{}" },
    };
    const messages = [_]prov.ChatMessage{
        .{ .role = .assistant, .content = "", .tool_calls = &calls },
        .{ .role = .tool, .content = "ok", .tool_call_id = "call-123" },
    };

    try std.testing.expectEqualStrings("write", findToolNameByCallId(&messages, "call-123").?);
    try std.testing.expect(findToolNameByCallId(&messages, "missing") == null);
}

test "tool parameter schemas must be JSON objects" {
    const allocator = std.testing.allocator;
    try validateSchema(allocator, "{\"type\":\"object\"}");
    try std.testing.expectError(error.ToolSchemaMustBeObject, validateSchema(allocator, "[]"));
}
