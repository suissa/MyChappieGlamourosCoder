const std = @import("std");
const builtin = @import("builtin");
const tool_mod = @import("tool.zig");
pub const Tool = tool_mod.Tool;
pub const ToolResult = tool_mod.ToolResult;

const BashArgs = struct {
    command: []const u8,
    timeout_ms: ?u64 = null,
    cwd: ?[]const u8 = null,
};

pub fn execute(allocator: std.mem.Allocator, io: std.Io, args_json: []const u8) !ToolResult {
    var parsed = std.json.parseFromSlice(BashArgs, allocator, args_json, .{ .ignore_unknown_fields = true }) catch |err| {
        const msg = try std.fmt.allocPrint(allocator, "JSON parse error in bash tool: {s}", .{@errorName(err)});
        return ToolResult{
            .success = false,
            .output = try allocator.dupe(u8, ""),
            .error_message = msg,
        };
    };
    defer parsed.deinit();

    const command = parsed.value.command;

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
        .reserve_amount = 4096,
        .stdout_limit = .unlimited,
        .stderr_limit = .unlimited,
    }) catch |err| {
        const msg = try std.fmt.allocPrint(allocator, "Failed to spawn child process for command '{s}': {s}", .{ command, @errorName(err) });
        return ToolResult{
            .success = false,
            .output = try allocator.dupe(u8, ""),
            .error_message = msg,
        };
    };
    defer allocator.free(run_result.stdout);
    defer allocator.free(run_result.stderr);

    const is_success = switch (run_result.term) {
        .exited => |code| code == 0,
        else => false,
    };

    var output_list: std.ArrayList(u8) = .empty;
    defer output_list.deinit(allocator);

    if (run_result.stdout.len > 0) {
        try output_list.appendSlice(allocator, run_result.stdout);
    }
    if (run_result.stderr.len > 0) {
        if (output_list.items.len > 0) try output_list.appendSlice(allocator, "\n[STDERR]\n");
        try output_list.appendSlice(allocator, run_result.stderr);
    }

    if (output_list.items.len == 0) {
        try output_list.appendSlice(allocator, "(Command produced no output)");
    }

    const full_output = try output_list.toOwnedSlice(allocator);

    var error_msg: ?[]const u8 = null;
    if (!is_success) {
        const term_code: u8 = switch (run_result.term) {
            .exited => |c| c,
            else => 1,
        };
        error_msg = try std.fmt.allocPrint(allocator, "Process exited with status code {d}", .{term_code});
    }

    return ToolResult{
        .success = is_success,
        .output = full_output,
        .error_message = error_msg,
    };
}

pub const tool_def = Tool{
    .name = "bash",
    .description = "Execute a command in the shell and return its combined stdout and stderr.",
    .parameters_json =
    \\{
    \\  "type": "object",
    \\  "properties": {
    \\    "command": { "type": "string", "description": "The command line string to execute" },
    \\    "timeout_ms": { "type": "integer", "description": "Optional timeout in milliseconds" }
    \\  },
    \\  "required": ["command"]
    \\}
    ,
    .execute_fn = execute,
};

test "bash tool echo" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;

    var res = try execute(allocator, io, "{\"command\": \"echo chappie_test_ok\"}");
    defer res.deinit(allocator);

    try std.testing.expect(res.success);
    try std.testing.expect(std.mem.indexOf(u8, res.output, "chappie_test_ok") != null);
}
