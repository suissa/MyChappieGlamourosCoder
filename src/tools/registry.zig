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
        return .{
            .tools = &default_tools,
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

test "tool registry retrieval and listing" {
    const reg = ToolRegistry.init();
    try std.testing.expect(reg.tools.len >= 8);
    try std.testing.expect(reg.get("bash") != null);
    try std.testing.expect(reg.get("view") != null);
    try std.testing.expect(reg.get("write") != null);
    try std.testing.expect(reg.get("edit") != null);
    try std.testing.expect(reg.get("non_existent") == null);
}
