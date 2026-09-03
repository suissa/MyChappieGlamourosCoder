const std = @import("std");
const builtin = @import("builtin");
const tool_mod = @import("tool.zig");
pub const Tool = tool_mod.Tool;
pub const ToolResult = tool_mod.ToolResult;

const BashArgs = struct {
    command: []const u8,
    cwd: ?[]const u8 = null,
};

pub fn execute(allocator: std.mem.Allocator, io: std.Io, args_json: []const u8) !ToolResult {
    var parsed = std.json.parseFromSlice(BashArgs, allocator, args_json, .{ .ignore_unknown_fields = true }) catch |err| {
        const msg = try std.fmt.allocPrint(allocator, "JSON parse error in bash tool: {s}", .{@errorName(err)});
        return .{ .success = false, .output = try allocator.dupe(u8, ""), .error_message = msg };
    };
    defer parsed.deinit();

    const command = parsed.value.command;
    if (command.len == 0) {
        return .{
            .success = false,
            .output = try allocator.dupe(u8, ""),
            .error_message = try allocator.dupe(u8, "command cannot be empty"),
        };
    }

    var argv_buf: [3][]const u8 = undefined;
    const argv: []const []const u8 = if (builtin.os.tag == .windows) blk: {
        argv_buf = .{ "cmd.exe", "/c", command };
        break :blk &argv_buf;
    } else blk: {
        argv_buf = .{ "/bin/sh", "-c", command };
        break :blk &argv_buf;
    };

    const run_result = std.process.run(allocator, io, .{
        .argv = argv,
        .cwd = if (parsed.value.cwd) |path| .{ .path = path } else .{ .inherit = {} },
        .reserve_amount = 4096,
        .stdout_limit = .limited(4 * 1024 * 1024),
        .stderr_limit = .limited(4 * 1024 * 1024),
    }) catch |err| {
        const msg = try std.fmt.allocPrint(allocator, "Failed to spawn child process for command '{s}': {s}", .{ command, @errorName(err) });
        return .{ .success = false, .output = try allocator.dupe(u8, ""), .error_message = msg };
    };
    defer allocator.free(run_result.stdout);
    defer allocator.free(run_result.stderr);

    const is_success = switch (run_result.term) {
        .exited => |code| code == 0,
        else => false,
    };

    var output: std.Io.Writer.Allocating = .init(allocator);
    defer output.deinit();

    if (run_result.stdout.len > 0) try output.writer.writeAll(run_result.stdout);
    if (run_result.stderr.len > 0) {
        if (output.written().len > 0) try output.writer.writeAll("\n[STDERR]\n");
        try output.writer.writeAll(run_result.stderr);
    }
    if (output.written().len == 0) try output.writer.writeAll("(Command produced no output)");

    var error_message: ?[]const u8 = null;
    if (!is_success) {
        error_message = switch (run_result.term) {
            .exited => |code| try std.fmt.allocPrint(allocator, "Process exited with status code {d}", .{code}),
            else => try std.fmt.allocPrint(allocator, "Process terminated: {any}", .{run_result.term}),
        };
    }

    return .{
        .success = is_success,
        .output = try output.toOwnedSlice(),
        .error_message = error_message,
    };
}

pub const tool_def = Tool{
    .name = "bash",
    .description = "Execute a shell command inside the current workspace and return bounded stdout/stderr. This tool is classified as dangerous and denied by default.",
    .parameters_json =
    \\{
    \\  "type": "object",
    \\  "properties": {
    \\    "command": { "type": "string", "description": "The command line string to execute" },
    \\    "cwd": { "type": "string", "description": "Optional relative working directory inside the workspace" }
    \\  },
    \\  "required": ["command"]
    \\}
    ,
    .execute_fn = execute,
};

test "bash tool definition stays dangerous and bounded" {
    try std.testing.expectEqualStrings("bash", tool_def.name);
    try std.testing.expect(std.mem.indexOf(u8, tool_def.parameters_json, "timeout_ms") == null);
}
