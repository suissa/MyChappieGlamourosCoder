const std = @import("std");
const tool_mod = @import("tool.zig");
pub const Tool = tool_mod.Tool;
pub const ToolResult = tool_mod.ToolResult;

const WriteArgs = struct {
    path: []const u8,
    content: []const u8,
};

pub fn execute(allocator: std.mem.Allocator, io: std.Io, args_json: []const u8) !ToolResult {
    var parsed = std.json.parseFromSlice(WriteArgs, allocator, args_json, .{ .ignore_unknown_fields = true }) catch |err| {
        const msg = try std.fmt.allocPrint(allocator, "JSON parse error in write tool: {s}", .{@errorName(err)});
        return ToolResult{
            .success = false,
            .output = try allocator.dupe(u8, ""),
            .error_message = msg,
        };
    };
    defer parsed.deinit();

    const path = parsed.value.path;
    const content = parsed.value.content;

    // Create parent directories if any
    if (std.fs.path.dirname(path)) |dir_path| {
        if (dir_path.len > 0) {
            const cwd = std.Io.Dir.cwd();
            cwd.createDirPath(io, dir_path) catch {};
        }
    }

    const cwd = std.Io.Dir.cwd();
    cwd.writeFile(io, .{ .sub_path = path, .data = content }) catch |err| {
        const msg = try std.fmt.allocPrint(allocator, "Failed to write file '{s}': {s}", .{ path, @errorName(err) });
        return ToolResult{
            .success = false,
            .output = try allocator.dupe(u8, ""),
            .error_message = msg,
        };
    };

    const success_msg = try std.fmt.allocPrint(allocator, "Successfully wrote {d} bytes to '{s}'", .{ content.len, path });
    return ToolResult{
        .success = true,
        .output = success_msg,
    };
}

pub const tool_def = Tool{
    .name = "write",
    .description = "Create or overwrite a file with the specified content. Parent directories are created automatically.",
    .parameters_json =
    \\{
    \\  "type": "object",
    \\  "properties": {
    \\    "path": { "type": "string", "description": "The destination file path" },
    \\    "content": { "type": "string", "description": "The full text content to write" }
    \\  },
    \\  "required": ["path", "content"]
    \\}
    ,
    .execute_fn = execute,
};

test "write tool execution" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;

    const test_path = "temp_test_dir/nested/test_write.txt";
    const cwd = std.Io.Dir.cwd();
    defer {
        cwd.deleteFile(io, test_path) catch {};
        cwd.deleteDir(io, "temp_test_dir/nested") catch {};
        cwd.deleteDir(io, "temp_test_dir") catch {};
    }

    var res = try execute(allocator, io, "{\"path\": \"temp_test_dir/nested/test_write.txt\", \"content\": \"hello chappie\"}");
    defer res.deinit(allocator);

    try std.testing.expect(res.success);
    const read_back = try cwd.readFileAlloc(io, test_path, allocator, .unlimited);
    defer allocator.free(read_back);
    try std.testing.expectEqualStrings("hello chappie", read_back);
}
