const std = @import("std");
const mychappie = @import("mychappie_coder");

test "config remains deterministic when process environment is not injected" {
    const cfg = mychappie.AppConfig.load(std.testing.io, ".", null);

    try std.testing.expectEqual(mychappie.llm.provider.ProviderType.mock, cfg.provider_type);
    try std.testing.expectEqualStrings("mock-chappie-v1", cfg.model);
    try std.testing.expect(cfg.api_key == null);
}

test "unknown tools fail closed" {
    const allocator = std.testing.allocator;
    const registry = mychappie.tools.ToolRegistry.init();

    var result = try registry.execute(allocator, std.testing.io, "does-not-exist", "{}");
    defer result.deinit(allocator);

    try std.testing.expect(!result.success);
    try std.testing.expect(result.error_message != null);
    try std.testing.expect(std.mem.indexOf(u8, result.error_message.?, "not found") != null);
}

test "dangerous shell tool is denied by default" {
    const permissions = mychappie.PermissionManager.init(false);

    try std.testing.expectEqual(mychappie.permission.PermissionLevel.dangerous, permissions.classifyTool("bash"));
    try std.testing.expect(!permissions.isAllowed("bash"));
    try std.testing.expect(permissions.isAllowed("view"));
    try std.testing.expect(permissions.isAllowed("write"));
}

test "agent permission gate prevents requested bash execution by default" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;
    const cwd = std.Io.Dir.cwd();
    const probe_path = "permission_gate_probe.txt";

    cwd.deleteFile(io, probe_path) catch {};
    defer cwd.deleteFile(io, probe_path) catch {};

    var agent = try mychappie.agent.CoderAgent.init(allocator, ".", .{ .max_steps = 3 });
    defer agent.deinit(allocator);

    try std.testing.expect(!agent.options.dangerously_skip_permissions);

    const output = try agent.executeTurn(allocator, io, "execute bash for permission regression");
    defer allocator.free(output);
    try std.testing.expect(output.len > 0);

    try std.testing.expectError(error.FileNotFound, cwd.openFile(io, probe_path, .{}));

    var saw_denial = false;
    for (agent.session.messages.items) |message| {
        if (message.role == .tool and std.mem.indexOf(u8, message.content, "Permission denied") != null) {
            saw_denial = true;
            break;
        }
    }
    try std.testing.expect(saw_denial);
}

test "direct agent response does not invoke filesystem write tool" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;
    const cwd = std.Io.Dir.cwd();
    const generated_path = "chappie_demo.txt";

    cwd.deleteFile(io, generated_path) catch {};
    defer cwd.deleteFile(io, generated_path) catch {};

    var agent = try mychappie.agent.CoderAgent.init(allocator, ".", .{ .max_steps = 3 });
    defer agent.deinit(allocator);

    const output = try agent.executeTurn(
        allocator,
        io,
        "Explique o estado atual do agente sem criar arquivos.",
    );
    defer allocator.free(output);

    try std.testing.expect(output.len > 0);
    try std.testing.expectError(error.FileNotFound, cwd.openFile(io, generated_path, .{}));
}
