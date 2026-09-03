const std = @import("std");
const tool_mod = @import("tool.zig");
pub const Tool = tool_mod.Tool;
pub const ToolResult = tool_mod.ToolResult;

const view_tool = @import("view.zig").tool_def;
const write_tool = @import("write.zig").tool_def;
const edit_tool = @import("edit.zig").tool_def;
const bash_tool = @import("bash.zig").tool_def;
const grep_tool = @import("grep.zig").tool_def;
const glob_tool = @import("glob.zig").tool_def;
const todos_tool = @import("todos.zig").tool_def;
const question_tool = @import("question.zig").tool_def;

pub const ToolRegistry = struct {
    tools: []const Tool,
    workspace_root: []const u8,

    pub const default_tools = [_]Tool{
        view_tool,
        write_tool,
        edit_tool,
        bash_tool,
        grep_tool,
        glob_tool,
        todos_tool,
        question_tool,
    };

    pub fn init() ToolRegistry {
        return initWithWorkspace(".");
    }

    pub fn initWithWorkspace(workspace_root: []const u8) ToolRegistry {
        return .{
            .tools = &default_tools,
            .workspace_root = workspace_root,
        };
    }

    pub fn get(self: ToolRegistry, name: []const u8) ?Tool {
        for (self.tools) |t| {
            if (std.mem.eql(u8, t.name, name)) {
                return t;
            }
        }
        return null;
    }

    pub fn execute(self: ToolRegistry, allocator: std.mem.Allocator, io: std.Io, name: []const u8, args_json: []const u8) !ToolResult {
        if (self.get(name)) |t| {
            // File-oriented tools are deliberately scoped to relative paths.
            // The CLI starts in the selected workspace; rejecting absolute and
            // parent-traversal paths prevents an LLM tool call from escaping it.
            if (hasWorkspaceEscape(allocator, name, args_json)) {
                return ToolResult{
                    .success = false,
                    .output = try allocator.dupe(u8, ""),
                    .error_message = try std.fmt.allocPrint(
                        allocator,
                        "Tool '{s}' attempted to access a path outside workspace '{s}'",
                        .{ name, self.workspace_root },
                    ),
                };
            }
            return t.execute(allocator, io, args_json);
        }
        const err_msg = try std.fmt.allocPrint(allocator, "Tool '{s}' not found in registry", .{name});
        return ToolResult{
            .success = false,
            .output = try allocator.dupe(u8, ""),
            .error_message = err_msg,
        };
    }
};

fn hasWorkspaceEscape(allocator: std.mem.Allocator, tool_name: []const u8, args_json: []const u8) bool {
    const key: ?[]const u8 = if (std.mem.eql(u8, tool_name, "view") or
        std.mem.eql(u8, tool_name, "write") or
        std.mem.eql(u8, tool_name, "edit"))
        "path"
    else if (std.mem.eql(u8, tool_name, "grep") or std.mem.eql(u8, tool_name, "glob"))
        "dir"
    else if (std.mem.eql(u8, tool_name, "bash"))
        "cwd"
    else
        null;

    const path_key = key orelse return false;
    var parsed = std.json.parseFromSlice(std.json.Value, allocator, args_json, .{}) catch return false;
    defer parsed.deinit();

    if (parsed.value != .object) return false;
    const value = parsed.value.object.get(path_key) orelse return false;
    if (value != .string) return false;
    return isEscapingPath(value.string);
}

fn isEscapingPath(path: []const u8) bool {
    if (path.len == 0 or std.mem.eql(u8, path, ".")) return false;
    if (std.fs.path.isAbsolute(path)) return true;

    var parts = std.mem.tokenizeAny(u8, path, "/\\");
    while (parts.next()) |part| {
        if (std.mem.eql(u8, part, "..")) return true;
    }
    return false;
}

test "tool registry retrieval and listing" {
    const reg = ToolRegistry.init();
    try std.testing.expect(reg.tools.len >= 8);
    try std.testing.expect(reg.get("bash") != null);
    try std.testing.expect(reg.get("view") != null);
    try std.testing.expect(reg.get("write") != null);
    try std.testing.expect(reg.get("edit") != null);
    try std.testing.expect(reg.get("non_existent") == null);
}

test "tool registry rejects workspace traversal before execution" {
    const allocator = std.testing.allocator;
    const reg = ToolRegistry.initWithWorkspace(".");

    var result = try reg.execute(allocator, std.testing.io, "view", "{\"path\":\"../../outside.txt\"}");
    defer result.deinit(allocator);

    try std.testing.expect(!result.success);
    try std.testing.expect(result.error_message != null);
    try std.testing.expect(std.mem.indexOf(u8, result.error_message.?, "outside workspace") != null);
}
