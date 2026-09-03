const std = @import("std");
const tool_mod = @import("../tools/tool.zig");
pub const Tool = tool_mod.Tool;

pub const Role = enum {
    system,
    user,
    assistant,
    tool,

    pub fn asString(self: Role) []const u8 {
        return switch (self) {
            .system => "system",
            .user => "user",
            .assistant => "assistant",
            .tool => "tool",
        };
    }
};

pub const ToolCall = struct {
    id: []const u8,
    name: []const u8,
    arguments_json: []const u8,

    pub fn clone(self: ToolCall, allocator: std.mem.Allocator) !ToolCall {
        const id = try allocator.dupe(u8, self.id);
        errdefer allocator.free(id);
        const name = try allocator.dupe(u8, self.name);
        errdefer allocator.free(name);
        const arguments_json = try allocator.dupe(u8, self.arguments_json);
        return .{ .id = id, .name = name, .arguments_json = arguments_json };
    }

    pub fn deinit(self: *ToolCall, allocator: std.mem.Allocator) void {
        allocator.free(self.id);
        allocator.free(self.name);
        allocator.free(self.arguments_json);
        self.* = undefined;
    }
};

pub const ChatMessage = struct {
    role: Role,
    content: []const u8,
    tool_calls: ?[]ToolCall = null,
    tool_call_id: ?[]const u8 = null,

    pub fn clone(self: ChatMessage, allocator: std.mem.Allocator) !ChatMessage {
        const content = try allocator.dupe(u8, self.content);
        errdefer allocator.free(content);

        const cloned_calls: ?[]ToolCall = if (self.tool_calls) |calls|
            try cloneToolCalls(allocator, calls)
        else
            null;
        errdefer deinitToolCalls(allocator, cloned_calls);

        const tool_call_id = if (self.tool_call_id) |id| try allocator.dupe(u8, id) else null;
        errdefer if (tool_call_id) |id| allocator.free(id);

        return .{
            .role = self.role,
            .content = content,
            .tool_calls = cloned_calls,
            .tool_call_id = tool_call_id,
        };
    }

    pub fn deinit(self: *ChatMessage, allocator: std.mem.Allocator) void {
        allocator.free(self.content);
        deinitToolCalls(allocator, self.tool_calls);
        if (self.tool_call_id) |id| allocator.free(id);
        self.* = undefined;
    }
};

fn cloneToolCalls(allocator: std.mem.Allocator, calls: []const ToolCall) ![]ToolCall {
    const owned_calls = try allocator.alloc(ToolCall, calls.len);
    var initialized: usize = 0;
    errdefer {
        for (owned_calls[0..initialized]) |*call| call.deinit(allocator);
        allocator.free(owned_calls);
    }

    for (calls, 0..) |call, index| {
        owned_calls[index] = try call.clone(allocator);
        initialized += 1;
    }
    return owned_calls;
}

fn deinitToolCalls(allocator: std.mem.Allocator, maybe_calls: ?[]ToolCall) void {
    if (maybe_calls) |calls| {
        for (calls) |*call| call.deinit(allocator);
        allocator.free(calls);
    }
}

pub const CompletionRequest = struct {
    messages: []const ChatMessage,
    system_prompt: []const u8 = "",
    tools: []const Tool = &.{},
    model: []const u8,
    temperature: f32 = 0.2,
};

pub const CompletionResponse = struct {
    content: ?[]const u8 = null,
    tool_calls: ?[]ToolCall = null,
    tokens_used: ?usize = null,

    pub fn deinit(self: *CompletionResponse, allocator: std.mem.Allocator) void {
        if (self.content) |content| allocator.free(content);
        deinitToolCalls(allocator, self.tool_calls);
        self.* = undefined;
    }
};

pub const ProviderType = enum {
    gemini,
    openai,
    anthropic,
    ollama,
    mock,
};

test "chat message clone owns all nested memory" {
    const allocator = std.testing.allocator;
    const calls = [_]ToolCall{
        .{ .id = "call-1", .name = "view", .arguments_json = "{\"path\":\"README.md\"}" },
    };
    const msg = ChatMessage{
        .role = .assistant,
        .content = "checking",
        .tool_calls = &calls,
    };
    var cloned = try msg.clone(allocator);
    defer cloned.deinit(allocator);

    try std.testing.expectEqualStrings("checking", cloned.content);
    try std.testing.expectEqualStrings("view", cloned.tool_calls.?[0].name);
}

test "completion request has total empty prompt and tools defaults" {
    const request = CompletionRequest{
        .messages = &.{},
        .model = "mock-model",
    };
    try std.testing.expectEqual(@as(usize, 0), request.system_prompt.len);
    try std.testing.expectEqual(@as(usize, 0), request.tools.len);
}
