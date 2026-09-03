const std = @import("std");
const tool_mod = @import("tool.zig");
pub const Tool = tool_mod.Tool;
pub const ToolResult = tool_mod.ToolResult;

const GlobArgs = struct {
    pattern: []const u8,
    dir: ?[]const u8 = null,
};

pub fn execute(allocator: std.mem.Allocator, io: std.Io, args_json: []const u8) !ToolResult {
    var parsed = std.json.parseFromSlice(GlobArgs, allocator, args_json, .{ .ignore_unknown_fields = true }) catch |err| {
        const msg = try std.fmt.allocPrint(allocator, "JSON parse error in glob tool: {s}", .{@errorName(err)});
        return ToolResult{
            .success = false,
            .output = try allocator.dupe(u8, ""),
            .error_message = msg,
        };
    };
    defer parsed.deinit();

    const pattern = parsed.value.pattern;
    const target_dir = parsed.value.dir orelse ".";

    const cwd = std.Io.Dir.cwd();
    var dir = cwd.openDir(io, target_dir, .{ .iterate = true }) catch |err| {
        const msg = try std.fmt.allocPrint(allocator, "Failed to open directory '{s}': {s}", .{ target_dir, @errorName(err) });
        return ToolResult{
            .success = false,
            .output = try allocator.dupe(u8, ""),
            .error_message = msg,
        };
    };
    defer dir.close(io);

    var walker = dir.walk(allocator) catch |err| {
        const msg = try std.fmt.allocPrint(allocator, "Failed to walk directory '{s}': {s}", .{ target_dir, @errorName(err) });
        return ToolResult{
            .success = false,
            .output = try allocator.dupe(u8, ""),
            .error_message = msg,
        };
    };
    defer walker.deinit();

    var out_list: std.ArrayList(u8) = .empty;
    defer out_list.deinit(allocator);

    var count: usize = 0;
    // Simple matching: if pattern starts with "*.", match extension; else substring match
    const is_ext_pattern = std.mem.startsWith(u8, pattern, "*.");
    const ext_target = if (is_ext_pattern) pattern[1..] else "";

    while (try walker.next(io)) |entry| {
        // Skip hidden and build dirs
        if (std.mem.indexOf(u8, entry.path, ".git") != null or
            std.mem.indexOf(u8, entry.path, "zig-cache") != null or
            std.mem.indexOf(u8, entry.path, "zig-out") != null or
            std.mem.indexOf(u8, entry.path, "legacy_go") != null or
            std.mem.indexOf(u8, entry.path, "node_modules") != null)
        {
            continue;
        }

        var matched = false;
        if (std.mem.eql(u8, pattern, "*") or std.mem.eql(u8, pattern, "**/*")) {
            matched = true;
        } else if (is_ext_pattern) {
            matched = std.mem.endsWith(u8, entry.path, ext_target);
        } else {
            matched = std.mem.indexOf(u8, entry.path, pattern) != null;
        }

        if (matched) {
            count += 1;
            const kind_str = if (entry.kind == .directory) "[DIR]  " else "[FILE] ";
            const line = try std.fmt.allocPrint(allocator, "{s} {s}\n", .{ kind_str, entry.path });
            defer allocator.free(line);
            try out_list.appendSlice(allocator, line);

            if (count >= 150) {
                try out_list.appendSlice(allocator, "... [Capped at 150 items] ...\n");
                break;
            }
        }
    }

    if (count == 0) {
        try out_list.appendSlice(allocator, "No files matched pattern.");
    }

    return ToolResult{
        .success = true,
        .output = try out_list.toOwnedSlice(allocator),
    };
}

pub const tool_def = Tool{
    .name = "glob",
    .description = "Find files and directories matching a wildcard or pattern (e.g. *.zig or filename substring).",
    .parameters_json = 
    \\{
    \\  "type": "object",
    \\  "properties": {
    \\    "pattern": { "type": "string", "description": "Glob or file pattern to match, e.g. *.zig" },
    \\    "dir": { "type": "string", "description": "Starting directory (default: .)" }
    \\  },
    \\  "required": ["pattern"]
    \\}
    ,
    .execute_fn = execute,
};

test "glob tool listing" {
    const allocator = std.testing.allocator;
    var threaded = std.Io.Threaded.init(allocator, .{ .environ = .{ .block = .global } });
    defer threaded.deinit();
    const io = threaded.io();

    const cwd = std.Io.Dir.cwd();
    try cwd.writeFile(io, .{ .sub_path = "temp_glob_target.zig", .data = "const x = 1;" });
    defer cwd.deleteFile(io, "temp_glob_target.zig") catch {};

    var res = try execute(allocator, io, "{\"pattern\": \"*.zig\", \"dir\": \".\"}");
    defer res.deinit(allocator);

    try std.testing.expect(res.success);
    try std.testing.expect(std.mem.indexOf(u8, res.output, "temp_glob_target.zig") != null);
}
