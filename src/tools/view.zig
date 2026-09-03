const std = @import("std");
const tool_mod = @import("tool.zig");
pub const Tool = tool_mod.Tool;
pub const ToolResult = tool_mod.ToolResult;

const ViewArgs = struct {
    path: []const u8,
    start_line: ?usize = null,
    end_line: ?usize = null,
};

pub fn execute(allocator: std.mem.Allocator, io: std.Io, args_json: []const u8) !ToolResult {
    var parsed = std.json.parseFromSlice(ViewArgs, allocator, args_json, .{ .ignore_unknown_fields = true }) catch |err| {
        const msg = try std.fmt.allocPrint(allocator, "JSON parse error in view tool: {s}", .{@errorName(err)});
        return ToolResult{
            .success = false,
            .output = try allocator.dupe(u8, ""),
            .error_message = msg,
        };
    };
    defer parsed.deinit();

    const path = parsed.value.path;
    const start_line = parsed.value.start_line orelse 1;
    const end_line = parsed.value.end_line orelse std.math.maxInt(usize);

    const cwd = std.Io.Dir.cwd();
    const content = cwd.readFileAlloc(io, path, allocator, .unlimited) catch |err| {
        const msg = try std.fmt.allocPrint(allocator, "Failed to read file '{s}': {s}", .{ path, @errorName(err) });
        return ToolResult{
            .success = false,
            .output = try allocator.dupe(u8, ""),
            .error_message = msg,
        };
    };
    defer allocator.free(content);

    var out_list: std.ArrayList(u8) = .empty;
    defer out_list.deinit(allocator);

    var lines = std.mem.splitScalar(u8, content, '\n');
    var current_line: usize = 1;
    var lines_shown: usize = 0;

    while (lines.next()) |raw_line| {
        const line = if (raw_line.len > 0 and raw_line[raw_line.len - 1] == '\r')
            raw_line[0 .. raw_line.len - 1]
        else
            raw_line;

        if (current_line >= start_line and current_line <= end_line) {
            const formatted = try std.fmt.allocPrint(allocator, "{d:4}: {s}\n", .{ current_line, line });
            defer allocator.free(formatted);
            try out_list.appendSlice(allocator, formatted);
            lines_shown += 1;
            if (lines_shown > 1000) {
                try out_list.appendSlice(allocator, "... [Truncated remaining lines for token limit] ...\n");
                break;
            }
        }
        current_line += 1;
    }

    const output_str = try out_list.toOwnedSlice(allocator);
    return ToolResult{
        .success = true,
        .output = output_str,
    };
}

pub const tool_def = Tool{
    .name = "view",
    .description = "Read the contents of a file with line numbers and optional line range (start_line, end_line).",
    .parameters_json =
    \\{
    \\  "type": "object",
    \\  "properties": {
    \\    "path": { "type": "string", "description": "The path of the file to read" },
    \\    "start_line": { "type": "integer", "description": "Optional start line number (1-based)" },
    \\    "end_line": { "type": "integer", "description": "Optional end line number (1-based, inclusive)" }
    \\  },
    \\  "required": ["path"]
    \\}
    ,
    .execute_fn = execute,
};

test "view tool execution" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;

    const cwd = std.Io.Dir.cwd();
    try cwd.writeFile(io, .{ .sub_path = "test_view_file.txt", .data = "line 1\nline 2\nline 3\n" });
    defer cwd.deleteFile(io, "test_view_file.txt") catch {};

    var res = try execute(allocator, io, "{\"path\": \"test_view_file.txt\", \"start_line\": 2, \"end_line\": 2}");
    defer res.deinit(allocator);

    try std.testing.expect(res.success);
    try std.testing.expect(std.mem.indexOf(u8, res.output, "2: line 2") != null);
    try std.testing.expect(std.mem.indexOf(u8, res.output, "1: line 1") == null);
}
