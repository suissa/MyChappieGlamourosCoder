const std = @import("std");
const tool_mod = @import("tool.zig");
pub const Tool = tool_mod.Tool;
pub const ToolResult = tool_mod.ToolResult;

pub const TodoItem = struct {
    id: usize,
    task: []const u8,
    done: bool,
};

pub const TodoStore = struct {
    items: std.ArrayList(TodoItem),
    next_id: usize,

    pub fn init(allocator: std.mem.Allocator) TodoStore {
        _ = allocator;
        return .{
            .items = .empty,
            .next_id = 1,
        };
    }

    pub fn deinit(self: *TodoStore, allocator: std.mem.Allocator) void {
        for (self.items.items) |item| {
            allocator.free(item.task);
        }
        self.items.deinit(allocator);
    }
};

var global_todos: std.ArrayList(TodoItem) = .empty;
var global_next_id: usize = 1;

const TodosArgs = struct {
    action: []const u8, // "add", "complete", "list", "clear"
    task: ?[]const u8 = null,
    id: ?usize = null,
};

pub fn execute(allocator: std.mem.Allocator, io: std.Io, args_json: []const u8) !ToolResult {
    _ = io;
    var parsed = std.json.parseFromSlice(TodosArgs, allocator, args_json, .{ .ignore_unknown_fields = true }) catch |err| {
        const msg = try std.fmt.allocPrint(allocator, "JSON parse error in todos tool: {s}", .{@errorName(err)});
        return ToolResult{
            .success = false,
            .output = try allocator.dupe(u8, ""),
            .error_message = msg,
        };
    };
    defer parsed.deinit();

    const action = parsed.value.action;

    var out_list: std.ArrayList(u8) = .empty;
    defer out_list.deinit(allocator);

    if (std.mem.eql(u8, action, "add")) {
        const task_desc = parsed.value.task orelse {
            return ToolResult{
                .success = false,
                .output = try allocator.dupe(u8, ""),
                .error_message = try allocator.dupe(u8, "'task' parameter is required for 'add' action"),
            };
        };
        const task_copy = try allocator.dupe(u8, task_desc);
        try global_todos.append(allocator, .{
            .id = global_next_id,
            .task = task_copy,
            .done = false,
        });
        const msg = try std.fmt.allocPrint(allocator, "Added task #{d}: {s}", .{ global_next_id, task_desc });
        defer allocator.free(msg);
        try out_list.appendSlice(allocator, msg);
        global_next_id += 1;
    } else if (std.mem.eql(u8, action, "complete")) {
        const target_id = parsed.value.id orelse {
            return ToolResult{
                .success = false,
                .output = try allocator.dupe(u8, ""),
                .error_message = try allocator.dupe(u8, "'id' parameter is required for 'complete' action"),
            };
        };
        var found = false;
        for (global_todos.items) |*item| {
            if (item.id == target_id) {
                item.done = true;
                found = true;
                const msg = try std.fmt.allocPrint(allocator, "Marked task #{d} as completed: {s}", .{ item.id, item.task });
                defer allocator.free(msg);
                try out_list.appendSlice(allocator, msg);
                break;
            }
        }
        if (!found) {
            const msg = try std.fmt.allocPrint(allocator, "Task with ID #{d} not found", .{target_id});
            return ToolResult{
                .success = false,
                .output = try allocator.dupe(u8, ""),
                .error_message = msg,
            };
        }
    } else if (std.mem.eql(u8, action, "clear")) {
        for (global_todos.items) |item| {
            allocator.free(item.task);
        }
        global_todos.deinit(allocator);
        global_todos = .empty;
        try out_list.appendSlice(allocator, "All tasks cleared.");
    } else { // "list"
        if (global_todos.items.len == 0) {
            try out_list.appendSlice(allocator, "No tasks in the plan.");
        } else {
            try out_list.appendSlice(allocator, "=== Current Task Plan ===\n");
            for (global_todos.items) |item| {
                const mark = if (item.done) "[✔]" else "[ ]";
                const line = try std.fmt.allocPrint(allocator, "{s} #{d}: {s}\n", .{ mark, item.id, item.task });
                defer allocator.free(line);
                try out_list.appendSlice(allocator, line);
            }
        }
    }

    return ToolResult{
        .success = true,
        .output = try out_list.toOwnedSlice(allocator),
    };
}

pub const tool_def = Tool{
    .name = "todos",
    .description = "Manage autonomous agent task plan (actions: add, complete, list, clear).",
    .parameters_json = 
    \\{
    \\  "type": "object",
    \\  "properties": {
    \\    "action": { "type": "string", "description": "One of: add, complete, list, clear" },
    \\    "task": { "type": "string", "description": "Task description (when action is add)" },
    \\    "id": { "type": "integer", "description": "Task ID (when action is complete)" }
    \\  },
    \\  "required": ["action"]
    \\}
    ,
    .execute_fn = execute,
};

test "todos tool lifecycle" {
    const allocator = std.testing.allocator;
    var threaded = std.Io.Threaded.init(allocator, .{ .environ = .{ .block = .global } });
    defer threaded.deinit();
    const io = threaded.io();

    var res_add = try execute(allocator, io, "{\"action\": \"add\", \"task\": \"Build Zig 0.16 agent\"}");
    defer res_add.deinit(allocator);
    try std.testing.expect(res_add.success);

    var res_list = try execute(allocator, io, "{\"action\": \"list\"}");
    defer res_list.deinit(allocator);
    try std.testing.expect(std.mem.indexOf(u8, res_list.output, "Build Zig 0.16 agent") != null);

    var res_clear = try execute(allocator, io, "{\"action\": \"clear\"}");
    defer res_clear.deinit(allocator);
    try std.testing.expect(res_clear.success);
}
