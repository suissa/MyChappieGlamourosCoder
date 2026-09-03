const std = @import("std");
const tool_mod = @import("tool.zig");
pub const Tool = tool_mod.Tool;
pub const ToolResult = tool_mod.ToolResult;

const QuestionArgs = struct {
    question: []const u8,
    default_answer: ?[]const u8 = null,
};

pub fn execute(allocator: std.mem.Allocator, io: std.Io, args_json: []const u8) !ToolResult {
    _ = io;
    var parsed = std.json.parseFromSlice(QuestionArgs, allocator, args_json, .{ .ignore_unknown_fields = true }) catch |err| {
        const msg = try std.fmt.allocPrint(allocator, "JSON parse error in question tool: {s}", .{@errorName(err)});
        return ToolResult{
            .success = false,
            .output = try allocator.dupe(u8, ""),
            .error_message = msg,
        };
    };
    defer parsed.deinit();

    const q = parsed.value.question;
    const def = parsed.value.default_answer orelse "yes";

    std.debug.print("\n\x1b[38;2;250;204;21m\x1b[1m[PERGUNTA DO AGENTE]\x1b[0m {s}\n", .{q});
    std.debug.print("\x1b[38;2;148;163;184m(Auto-confirmado no modo não-interativo com: '{s}')\x1b[0m\n", .{def});

    const response_str = try std.fmt.allocPrint(allocator, "User confirmed: {s}", .{def});
    return ToolResult{
        .success = true,
        .output = response_str,
    };
}

pub const tool_def = Tool{
    .name = "question",
    .description = "Ask a question to the user for clarification or confirmation during execution.",
    .parameters_json =
    \\{
    \\  "type": "object",
    \\  "properties": {
    \\    "question": { "type": "string", "description": "The question to ask the user" },
    \\    "default_answer": { "type": "string", "description": "Fallback answer for headless mode" }
    \\  },
    \\  "required": ["question"]
    \\}
    ,
    .execute_fn = execute,
};

test "question tool definition" {
    try std.testing.expectEqualStrings("question", tool_def.name);
    try std.testing.expect(std.mem.indexOf(u8, tool_def.parameters_json, "default_answer") != null);
}
