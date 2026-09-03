const std = @import("std");
const tool_mod = @import("tool.zig");
pub const Tool = tool_mod.Tool;
pub const ToolResult = tool_mod.ToolResult;

const GrepArgs = struct {
    query: []const u8,
    dir: ?[]const u8 = null,
    case_sensitive: ?bool = true,
};

pub fn execute(allocator: std.mem.Allocator, io: std.Io, args_json: []const u8) !ToolResult {
    var parsed = std.json.parseFromSlice(GrepArgs, allocator, args_json, .{ .ignore_unknown_fields = true }) catch |err| {
        const msg = try std.fmt.allocPrint(allocator, "JSON parse error in grep tool: {s}", .{@errorName(err)});
        return ToolResult{ .success = false, .output = try allocator.dupe(u8, ""), .error_message = msg };
    };
    defer parsed.deinit();

    const query = parsed.value.query;
    const target_dir = parsed.value.dir orelse ".";
    const case_sensitive = parsed.value.case_sensitive orelse true;

    if (query.len == 0) {
        return ToolResult{ .success = false, .output = try allocator.dupe(u8, ""), .error_message = try allocator.dupe(u8, "Query string cannot be empty") };
    }

    const cwd = std.Io.Dir.cwd();
    var dir = cwd.openDir(io, target_dir, .{ .iterate = true }) catch |err| {
        const msg = try std.fmt.allocPrint(allocator, "Failed to open directory '{s}': {s}", .{ target_dir, @errorName(err) });
        return ToolResult{ .success = false, .output = try allocator.dupe(u8, ""), .error_message = msg };
    };
    defer dir.close(io);

    var walker = dir.walk(allocator) catch |err| {
        const msg = try std.fmt.allocPrint(allocator, "Failed to walk directory '{s}': {s}", .{ target_dir, @errorName(err) });
        return ToolResult{ .success = false, .output = try allocator.dupe(u8, ""), .error_message = msg };
    };
    defer walker.deinit();

    var out_list: std.ArrayList(u8) = .empty;
    defer out_list.deinit(allocator);
    var match_count: usize = 0;

    while (try walker.next(io)) |entry| {
        if (entry.kind != .file) continue;
        if (std.mem.indexOf(u8, entry.path, ".git") != null or
            std.mem.indexOf(u8, entry.path, "zig-cache") != null or
            std.mem.indexOf(u8, entry.path, "zig-out") != null or
            std.mem.indexOf(u8, entry.path, "legacy_go") != null or
            std.mem.indexOf(u8, entry.path, "node_modules") != null) continue;

        const file_content = dir.readFileAlloc(io, entry.path, allocator, .unlimited) catch continue;
        defer allocator.free(file_content);

        var lines = std.mem.splitScalar(u8, file_content, '\n');
        var line_num: usize = 1;
        while (lines.next()) |raw_line| {
            const line = if (raw_line.len > 0 and raw_line[raw_line.len - 1] == '\r') raw_line[0 .. raw_line.len - 1] else raw_line;
            const found = if (case_sensitive)
                std.mem.indexOf(u8, line, query) != null
            else
                std.ascii.indexOfIgnoreCase(line, query) != null;

            if (found) {
                match_count += 1;
                const formatted = try std.fmt.allocPrint(allocator, "{s}:{d}: {s}\n", .{ entry.path, line_num, line });
                defer allocator.free(formatted);
                try out_list.appendSlice(allocator, formatted);
                if (match_count >= 100) {
                    try out_list.appendSlice(allocator, "... [Capped at 100 matches] ...\n");
                    break;
                }
            }
            line_num += 1;
        }
        if (match_count >= 100) break;
    }

    if (match_count == 0) try out_list.appendSlice(allocator, "No matches found for query.");
    return ToolResult{ .success = true, .output = try out_list.toOwnedSlice(allocator) };
}

pub const tool_def = Tool{
    .name = "grep",
    .description = "Recursively search for a string pattern across files in a directory.",
    .parameters_json =
    \\{
    \\  "type": "object",
    \\  "properties": {
    \\    "query": { "type": "string", "description": "The search pattern to locate" },
    \\    "dir": { "type": "string", "description": "Directory to search within (default: .)" },
    \\    "case_sensitive": { "type": "boolean", "description": "Case sensitive match (default: true)" }
    \\  },
    \\  "required": ["query"]
    \\}
    ,
    .execute_fn = execute,
};

test "grep tool search" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;

    const test_file = "test_grep_target.txt";
    const cwd = std.Io.Dir.cwd();
    try cwd.writeFile(io, .{ .sub_path = test_file, .data = "alpha\nbravo_unique_token\ncharlie\n" });
    defer cwd.deleteFile(io, test_file) catch {};

    var res = try execute(allocator, io, "{\"query\": \"bravo_unique_token\", \"dir\": \".\"}");
    defer res.deinit(allocator);

    try std.testing.expect(res.success);
    try std.testing.expect(std.mem.indexOf(u8, res.output, "bravo_unique_token") != null);
}
