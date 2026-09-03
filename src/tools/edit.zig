const std = @import("std");
const tool_mod = @import("tool.zig");
pub const Tool = tool_mod.Tool;
pub const ToolResult = tool_mod.ToolResult;

const EditArgs = struct {
    path: []const u8,
    old_string: []const u8,
    new_string: []const u8,
    allow_multiple: ?bool = false,
};

pub fn execute(allocator: std.mem.Allocator, io: std.Io, args_json: []const u8) !ToolResult {
    var parsed = std.json.parseFromSlice(EditArgs, allocator, args_json, .{ .ignore_unknown_fields = true }) catch |err| {
        const msg = try std.fmt.allocPrint(allocator, "JSON parse error in edit tool: {s}", .{@errorName(err)});
        return ToolResult{
            .success = false,
            .output = try allocator.dupe(u8, ""),
            .error_message = msg,
        };
    };
    defer parsed.deinit();

    const path = parsed.value.path;
    const old_str = parsed.value.old_string;
    const new_str = parsed.value.new_string;
    const allow_multiple = parsed.value.allow_multiple orelse false;

    if (old_str.len == 0) {
        return ToolResult{
            .success = false,
            .output = try allocator.dupe(u8, ""),
            .error_message = try allocator.dupe(u8, "old_string cannot be empty"),
        };
    }

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

    // Count occurrences of old_str
    var count: usize = 0;
    var search_idx: usize = 0;
    while (search_idx <= content.len) {
        if (std.mem.indexOfPos(u8, content, search_idx, old_str)) |found| {
            count += 1;
            search_idx = found + old_str.len;
        } else {
            break;
        }
    }

    if (count == 0) {
        const msg = try std.fmt.allocPrint(allocator, "Target string not found in '{s}'. Please ensure exact match including whitespace.", .{path});
        return ToolResult{
            .success = false,
            .output = try allocator.dupe(u8, ""),
            .error_message = msg,
        };
    }

    if (count > 1 and !allow_multiple) {
        const msg = try std.fmt.allocPrint(allocator, "Target string occurs {d} times in '{s}'. Please provide more context lines for unique replacement or set allow_multiple=true.", .{ count, path });
        return ToolResult{
            .success = false,
            .output = try allocator.dupe(u8, ""),
            .error_message = msg,
        };
    }

    // Perform replacement
    var new_content_list: std.ArrayList(u8) = .empty;
    defer new_content_list.deinit(allocator);

    var last_idx: usize = 0;
    while (last_idx <= content.len) {
        if (std.mem.indexOfPos(u8, content, last_idx, old_str)) |found| {
            try new_content_list.appendSlice(allocator, content[last_idx..found]);
            try new_content_list.appendSlice(allocator, new_str);
            last_idx = found + old_str.len;
            if (!allow_multiple) {
                try new_content_list.appendSlice(allocator, content[last_idx..]);
                break;
            }
        } else {
            try new_content_list.appendSlice(allocator, content[last_idx..]);
            break;
        }
    }

    const updated_content = try new_content_list.toOwnedSlice(allocator);
    defer allocator.free(updated_content);

    cwd.writeFile(io, .{ .sub_path = path, .data = updated_content }) catch |err| {
        const msg = try std.fmt.allocPrint(allocator, "Failed to write updated file '{s}': {s}", .{ path, @errorName(err) });
        return ToolResult{
            .success = false,
            .output = try allocator.dupe(u8, ""),
            .error_message = msg,
        };
    };

    const diff_summary = try std.fmt.allocPrint(
        allocator,
        "Successfully replaced {d} occurrence(s) in '{s}'.\n--- old\n+++ new\n@@ replacement @@\n-{s}\n+{s}",
        .{ count, path, old_str, new_str },
    );
    return ToolResult{
        .success = true,
        .output = diff_summary,
    };
}

pub const tool_def = Tool{
    .name = "edit",
    .description = "Surgically edit a file by finding old_string and replacing it with new_string. old_string must match uniquely unless allow_multiple is true.",
    .parameters_json = 
    \\{
    \\  "type": "object",
    \\  "properties": {
    \\    "path": { "type": "string", "description": "The path of the file to edit" },
    \\    "old_string": { "type": "string", "description": "The exact block of text to replace" },
    \\    "new_string": { "type": "string", "description": "The replacement text" },
    \\    "allow_multiple": { "type": "boolean", "description": "Allow replacing multiple occurrences" }
    \\  },
    \\  "required": ["path", "old_string", "new_string"]
    \\}
    ,
    .execute_fn = execute,
};

test "edit tool single replacement" {
    const allocator = std.testing.allocator;
    var threaded = std.Io.Threaded.init(allocator, .{ .environ = .{ .block = .global } });
    defer threaded.deinit();
    const io = threaded.io();

    const test_path = "test_edit_file.txt";
    const cwd = std.Io.Dir.cwd();
    try cwd.writeFile(io, .{ .sub_path = test_path, .data = "const a = 10;\nconst b = 20;\n" });
    defer cwd.deleteFile(io, test_path) catch {};

    var res = try execute(allocator, io, "{\"path\": \"test_edit_file.txt\", \"old_string\": \"const a = 10;\", \"new_string\": \"const a = 42;\"}");
    defer res.deinit(allocator);

    try std.testing.expect(res.success);
    const read_back = try cwd.readFileAlloc(io, test_path, allocator, .unlimited);
    defer allocator.free(read_back);
    try std.testing.expectEqualStrings("const a = 42;\nconst b = 20;\n", read_back);
}
