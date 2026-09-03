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
const todos_mod = @import("todos.zig");
const todos_tool = todos_mod.tool_def;
const question_tool = @import("question.zig").tool_def;

pub const ToolRegistry = struct {
    tools: []const Tool,
    todos: todos_mod.TodoStore,

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
            .todos = todos_mod.TodoStore.init(),
        };
    }

    pub fn deinit(self: *ToolRegistry, allocator: std.mem.Allocator) void {
        self.todos.deinit(allocator);
        self.* = undefined;
    }

    pub fn get(self: ToolRegistry, name: []const u8) ?Tool {
        for (self.tools) |tool| {
            if (std.mem.eql(u8, tool.name, name)) return tool;
        }
        return null;
    }

    pub fn execute(self: *ToolRegistry, allocator: std.mem.Allocator, io: std.Io, name: []const u8, args_json: []const u8) !ToolResult {
        if (std.mem.eql(u8, name, "todos")) {
            return todos_mod.executeWithStore(&self.todos, allocator, io, args_json);
        }

        if (self.get(name)) |tool| {
            return tool.execute(allocator, io, args_json);
        }

        return .{
            .success = false,
            .output = try allocator.dupe(u8, ""),
            .error_message = try std.fmt.allocPrint(allocator, "Tool '{s}' not found in registry", .{name}),
        };
    }
};

test "tool registry retrieval and listing" {
    const allocator = std.testing.allocator;
    var registry = ToolRegistry.init();
    defer registry.deinit(allocator);

    try std.testing.expect(registry.tools.len >= 8);
    try std.testing.expect(registry.get("bash") != null);
    try std.testing.expect(registry.get("view") != null);
    try std.testing.expect(registry.get("write") != null);
    try std.testing.expect(registry.get("edit") != null);
    try std.testing.expect(registry.get("non_existent") == null);
}

test "tool registries isolate todo state" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;

    var first = ToolRegistry.init();
    defer first.deinit(allocator);
    var second = ToolRegistry.init();
    defer second.deinit(allocator);

    var add = try first.execute(allocator, io, "todos", "{\"action\":\"add\",\"task\":\"isolated\"}");
    defer add.deinit(allocator);
    try std.testing.expect(add.success);

    var second_list = try second.execute(allocator, io, "todos", "{\"action\":\"list\"}");
    defer second_list.deinit(allocator);
    try std.testing.expectEqualStrings("No tasks in the plan.", second_list.output);
}
