const std = @import("std");
const prov = @import("provider.zig");
pub const CompletionRequest = prov.CompletionRequest;
pub const CompletionResponse = prov.CompletionResponse;
pub const ToolCall = prov.ToolCall;

pub const MockProvider = struct {
    step_count: usize = 0,

    pub fn init() MockProvider {
        return .{};
    }

    pub fn send(self: *MockProvider, allocator: std.mem.Allocator, io: std.Io, request: CompletionRequest) !CompletionResponse {
        _ = io;
        self.step_count += 1;

        // Inspect the latest message
        const last_msg = if (request.messages.len > 0) request.messages[request.messages.len - 1] else null;

        // If the previous turn was a tool response, finish the task
        if (last_msg != null and last_msg.?.role == .tool) {
            const final_text = try std.fmt.allocPrint(
                allocator,
                "Tarefa concluída com sucesso pelo MyChappie Glamouros Coder no ambiente Zig v0.16!\nResultado da ferramenta recebido e verificado.",
                .{},
            );
            return CompletionResponse{
                .content = final_text,
                .tool_calls = null,
                .tokens_used = 150,
            };
        }

        // If prompt asks to create/write a file, emit a tool call to 'write'
        if (last_msg != null and (std.mem.indexOf(u8, last_msg.?.content, "Crie") != null or
            std.mem.indexOf(u8, last_msg.?.content, "write") != null or
            std.mem.indexOf(u8, last_msg.?.content, "teste.txt") != null))
        {
            var calls = try allocator.alloc(ToolCall, 1);
            calls[0] = ToolCall{
                .id = try allocator.dupe(u8, "call_mock_write_01"),
                .name = try allocator.dupe(u8, "write"),
                .arguments_json = try allocator.dupe(u8, "{\"path\": \"chappie_demo.txt\", \"content\": \"Criado autonomamente por MyChappie Glamouros Coder (Zig v0.16)\"}"),
            };
            return CompletionResponse{
                .content = try allocator.dupe(u8, "Vou criar o arquivo solicitado utilizando a ferramenta 'write'."),
                .tool_calls = calls,
                .tokens_used = 80,
            };
        }

        // Default direct response
        const resp = try std.fmt.allocPrint(
            allocator,
            "Olá! Sou o MyChappie Glamouros Coder, assistente inteligente autônomo nativo em Zig v0.16.\nRecebi sua mensagem: \"{s}\"",
            .{if (last_msg != null) last_msg.?.content else ""},
        );

        return CompletionResponse{
            .content = resp,
            .tool_calls = null,
            .tokens_used = 120,
        };
    }
};

test "mock provider step progression" {
    const allocator = std.testing.allocator;
    var threaded = std.Io.Threaded.init(allocator, .{ .environ = .{ .block = .global } });
    defer threaded.deinit();
    const io = threaded.io();

    var mock = MockProvider.init();
    const user_msg = [_]prov.ChatMessage{
        .{ .role = .user, .content = "Crie um arquivo teste.txt" },
    };

    var resp1 = try mock.send(allocator, io, .{
        .messages = &user_msg,
        .model = "mock-model",
    });
    defer resp1.deinit(allocator);

    try std.testing.expect(resp1.tool_calls != null);
    try std.testing.expectEqualStrings("write", resp1.tool_calls.?[0].name);

    // Follow up with tool message
    const tool_msg = [_]prov.ChatMessage{
        .{ .role = .user, .content = "Crie um arquivo teste.txt" },
        .{ .role = .tool, .content = "Successfully wrote 50 bytes", .tool_call_id = "call_mock_write_01" },
    };

    var resp2 = try mock.send(allocator, io, .{
        .messages = &tool_msg,
        .model = "mock-model",
    });
    defer resp2.deinit(allocator);

    try std.testing.expect(resp2.tool_calls == null);
    try std.testing.expect(resp2.content != null);
}
