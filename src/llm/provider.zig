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
        return .{
            .id = try allocator.dupe(u8, self.id),
            .name = try allocator.dupe(u8, self.name),
            .arguments_json = try allocator.dupe(u8, self.arguments_json),
        };
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
        var cloned_calls: ?[]ToolCall = null;
        if (self.tool_calls) |calls| {
            var list: std.ArrayList(ToolCall) = .empty;
            defer list.deinit(allocator);
            for (calls) |c| {
                try list.append(allocator, try c.clone(allocator));
            }
            cloned_calls = try list.toOwnedSlice(allocator);
        }

        return .{
            .role = self.role,
            .content = try allocator.dupe(u8, self.content),
            .tool_calls = cloned_calls,
            .tool_call_id = if (self.tool_call_id) |id| try allocator.dupe(u8, id) else null,
        };
    }

    pub fn deinit(self: *ChatMessage, allocator: std.mem.Allocator) void {
        allocator.free(self.content);
        if (self.tool_calls) |calls| {
            for (calls) |*c| {
                c.deinit(allocator);
            }
            allocator.free(calls);
        }
        if (self.tool_call_id) |id| {
            allocator.free(id);
        }
        self.* = undefined;
    }
};

pub const CompletionRequest = struct {
    messages: []const ChatMessage,
    system_prompt: ?[]const u8 = null,
    tools: ?[]const Tool = null,
    model: []const u8,
    temperature: f32 = 0.2,
};

pub const CompletionResponse = struct {
    content: ?[]const u8 = null,
    tool_calls: ?[]ToolCall = null,
    tokens_used: ?usize = null,

    pub fn deinit(self: *CompletionResponse, allocator: std.mem.Allocator) void {
        if (self.content) |c| {
            allocator.free(c);
        }
        if (self.tool_calls) |calls| {
            for (calls) |*c| {
                c.deinit(allocator);
            }
            allocator.free(calls);
        }
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

test "chat message clone and deinit" {
    const allocator = std.testing.allocator;
    var msg = ChatMessage{
        .role = .user,
        .content = "hello world",
    };
    var cloned = try msg.clone(allocator);
    defer cloned.deinit(allocator);

    try std.testing.expectEqualStrings("hello world", cloned.content);
    try std.testing.expect(cloned.role == .user);
}
