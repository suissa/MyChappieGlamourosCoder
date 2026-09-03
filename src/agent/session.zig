const std = @import("std");
const prov = @import("../llm/provider.zig");
pub const ChatMessage = prov.ChatMessage;
pub const Role = prov.Role;
pub const ToolCall = prov.ToolCall;

pub const Session = struct {
    id: []const u8,
    workspace_root: []const u8,
    messages: std.ArrayList(ChatMessage),
    turns_count: usize = 0,
    tokens_total: usize = 0,

    pub fn init(allocator: std.mem.Allocator, id: []const u8, workspace_root: []const u8) !Session {
        return .{
            .id = try allocator.dupe(u8, id),
            .workspace_root = try allocator.dupe(u8, workspace_root),
            .messages = .empty,
            .turns_count = 0,
            .tokens_total = 0,
        };
    }

    pub fn deinit(self: *Session, allocator: std.mem.Allocator) void {
        allocator.free(self.id);
        allocator.free(self.workspace_root);
        for (self.messages.items) |*msg| {
            msg.deinit(allocator);
        }
        self.messages.deinit(allocator);
        self.* = undefined;
    }

    pub fn addMessage(self: *Session, allocator: std.mem.Allocator, msg: ChatMessage) !void {
        const cloned = try msg.clone(allocator);
        try self.messages.append(allocator, cloned);
    }

    pub fn addTurn(self: *Session, allocator: std.mem.Allocator, role: Role, text: []const u8) !void {
        const msg = ChatMessage{
            .role = role,
            .content = text,
        };
        try self.addMessage(allocator, msg);
        if (role == .user) {
            self.turns_count += 1;
        }
    }
};

test "session lifecycle and message recording" {
    const allocator = std.testing.allocator;
    var s = try Session.init(allocator, "test-sess-001", ".");
    defer s.deinit(allocator);

    try s.addTurn(allocator, .user, "Olá MyChappie");
    try s.addTurn(allocator, .assistant, "Olá! Como posso codificar para você hoje?");

    try std.testing.expectEqual(@as(usize, 1), s.turns_count);
    try std.testing.expectEqual(@as(usize, 2), s.messages.items.len);
    try std.testing.expectEqualStrings("Olá MyChappie", s.messages.items[0].content);
}
