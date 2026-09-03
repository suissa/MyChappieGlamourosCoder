const std = @import("std");
const prov = @import("../llm/provider.zig");
const mock_prov = @import("../llm/mock.zig");
const session_mod = @import("session.zig");
const coord_mod = @import("coordinator.zig");
const reg_mod = @import("../tools/registry.zig");
const perm_mod = @import("../permission/permission.zig");
const glamour = @import("../glamour.zig").Glamour;

pub const AgentOptions = struct {
    max_steps: usize = 10,
    model: []const u8 = "mock-chappie-v1",
    dangerously_skip_permissions: bool = false,
};

pub const CoderAgent = struct {
    coordinator: coord_mod.Coordinator,
    registry: reg_mod.ToolRegistry,
    permissions: perm_mod.PermissionManager,
    session: session_mod.Session,
    mock_llm: mock_prov.MockProvider,
    options: AgentOptions,

    pub fn init(allocator: std.mem.Allocator, workspace_root: []const u8, options: AgentOptions) !CoderAgent {
        const sess = try session_mod.Session.init(allocator, "chappie-session-current", workspace_root);
        return .{
            .coordinator = coord_mod.Coordinator.init(.coder),
            .registry = reg_mod.ToolRegistry.init(),
            .permissions = perm_mod.PermissionManager.init(options.dangerously_skip_permissions),
            .session = sess,
            .mock_llm = mock_prov.MockProvider.init(),
            .options = options,
        };
    }

    pub fn deinit(self: *CoderAgent, allocator: std.mem.Allocator) void {
        self.registry.deinit(allocator);
        self.session.deinit(allocator);
        self.* = undefined;
    }

    pub fn executeTurn(self: *CoderAgent, allocator: std.mem.Allocator, io: std.Io, user_prompt: []const u8) ![]const u8 {
        try self.session.addTurn(allocator, .user, user_prompt);

        glamour.printStatus("EXECUÇÃO", "MyChappie Glamouros Coder iniciou o raciocínio...");

        const system_prompt = try self.coordinator.getCombinedPrompt(allocator);
        defer allocator.free(system_prompt);

        var current_step: usize = 0;
        var last_response_text: ?[]const u8 = null;

        while (current_step < self.options.max_steps) : (current_step += 1) {
            const req = prov.CompletionRequest{
                .messages = self.session.messages.items,
                .system_prompt = system_prompt,
                .tools = self.registry.tools,
                .model = self.options.model,
            };

            var llm_response = try self.mock_llm.send(allocator, io, req);
            defer llm_response.deinit(allocator);

            if (llm_response.content) |text| {
                if (last_response_text) |prev| allocator.free(prev);
                last_response_text = try allocator.dupe(u8, text);
            }

            if (llm_response.tool_calls) |calls| {
                if (calls.len > 0) {
                    for (calls) |call| {
                        glamour.printToolCall(call.name, call.arguments_json);

                        if (!self.permissions.isAllowed(call.name)) {
                            const denied = try std.fmt.allocPrint(
                                allocator,
                                "Permission denied: tool '{s}' is classified as dangerous. Set dangerously_skip_permissions=true only for an explicitly trusted execution context.",
                                .{call.name},
                            );
                            defer allocator.free(denied);

                            glamour.printToolResult(call.name, false, denied);
                            try self.session.addMessage(allocator, .{
                                .role = .tool,
                                .content = denied,
                                .tool_call_id = call.id,
                            });
                            continue;
                        }

                        var tool_res = try self.registry.execute(allocator, io, call.name, call.arguments_json);
                        defer tool_res.deinit(allocator);

                        const preview = if (tool_res.output.len > 120) tool_res.output[0..120] else tool_res.output;
                        glamour.printToolResult(call.name, tool_res.success, preview);

                        try self.session.addMessage(allocator, .{
                            .role = .tool,
                            .content = if (tool_res.success) tool_res.output else (tool_res.error_message orelse tool_res.output),
                            .tool_call_id = call.id,
                        });
                    }
                    continue;
                }
            }

            if (llm_response.content) |final_text| {
                try self.session.addTurn(allocator, .assistant, final_text);
            }
            break;
        }

        return last_response_text orelse try allocator.dupe(u8, "Tarefa concluída.");
    }
};

test "coder agent initialization is side-effect free and permissions are safe by default" {
    const allocator = std.testing.allocator;

    var agent = try CoderAgent.init(allocator, ".", .{ .max_steps = 5 });
    defer agent.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 5), agent.options.max_steps);
    try std.testing.expect(agent.registry.get("write") != null);
    try std.testing.expectEqual(@as(usize, 0), agent.mock_llm.step_count);
    try std.testing.expect(!agent.permissions.skip_all);
    try std.testing.expect(!agent.permissions.isAllowed("bash"));
}
