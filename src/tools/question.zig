const std = @import("std");
const tool_mod = @import("tool.zig");
pub const Tool = tool_mod.Tool;
pub const ToolResult = tool_mod.ToolResult;

const QuestionArgs = struct {
    question: []const u8,
    default_answer: ?[]const u8 = null,
};

/// The core agent is intentionally headless: it must never fabricate a human
/// confirmation. A caller may provide an explicit default_answer when the
/// answer is part of its own policy; otherwise the tool reports that human
/// input is required so the orchestration layer can suspend/resume the turn.
pub fn execute(allocator: std.mem.Allocator, io: std.Io, args_json: []const u8) !ToolResult {
    _ = io;
    var parsed = std.json.parseFromSlice(QuestionArgs, allocator, args_json, .{ .ignore_unknown_fields = true }) catch |err| {
        const msg = try std.fmt.allocPrint(allocator, "JSON parse error in question tool: {s}", .{@errorName(err)});
        return .{
            .success = false,
            .output = try allocator.dupe(u8, ""),
            .error_message = msg,
        };
    };
    defer parsed.deinit();

    const question = parsed.value.question;
    if (question.len == 0) {
        return .{
            .success = false,
            .output = try allocator.dupe(u8, ""),
            .error_message = try allocator.dupe(u8, "question cannot be empty"),
        };
    }

    if (parsed.value.default_answer) |answer| {
        const response = try std.fmt.allocPrint(
            allocator,
            "Policy-provided answer to '{s}': {s}",
            .{ question, answer },
        );
        return .{ .success = true, .output = response };
    }

    return .{
        .success = false,
        .output = try allocator.dupe(u8, ""),
        .error_message = try std.fmt.allocPrint(
            allocator,
            "Human input required: {s}",
            .{question},
        ),
    };
}

pub const tool_def = Tool{
    .name = "question",
    .description = "Request clarification or confirmation. Without an explicit policy-provided default_answer, execution fails closed with Human input required instead of auto-confirming.",
    .parameters_json =
    \\{
    \\  "type": "object",
    \\  "properties": {
    \\    "question": { "type": "string", "description": "The question that requires human or policy input" },
    \\    "default_answer": { "type": "string", "description": "Optional answer explicitly supplied by the caller's policy for headless execution" }
    \\  },
    \\  "required": ["question"]
    \\}
    ,
    .execute_fn = execute,
};

test "question tool fails closed without explicit answer" {
    const allocator = std.testing.allocator;
    var result = try execute(allocator, std.testing.io, "{\"question\":\"Proceed?\"}");
    defer result.deinit(allocator);

    try std.testing.expect(!result.success);
    try std.testing.expect(result.error_message != null);
    try std.testing.expect(std.mem.indexOf(u8, result.error_message.?, "Human input required") != null);
}

test "question tool accepts explicit policy answer" {
    const allocator = std.testing.allocator;
    var result = try execute(
        allocator,
        std.testing.io,
        "{\"question\":\"Proceed?\",\"default_answer\":\"yes\"}",
    );
    defer result.deinit(allocator);

    try std.testing.expect(result.success);
    try std.testing.expect(std.mem.indexOf(u8, result.output, "yes") != null);
}
