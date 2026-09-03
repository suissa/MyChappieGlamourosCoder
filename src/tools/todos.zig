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
    items: std.ArrayList(TodoItem) = .empty,
    next_id: usize = 1,

    pub fn init() TodoStore {
        return .{};
    }

    pub fn deinit(self: *TodoStore, allocator: std.mem.Allocator) void {
        self.clear(allocator);
        self.* = undefined;
    }

    pub fn clear(self: *TodoStore, allocator: std.mem.Allocator) void {
        for (self.items.items) |item| allocator.free(item.task);
        self.items.deinit(allocator);
        self.items = .empty;
        self.next_id = 1;
    }
};

const TodosArgs = struct {
    action: []const u8,
    task: ?[]const u8 = null,
    id: ?usize = null,
};

pub fn executeWithStore(store: *TodoStore, allocator: std.mem.Allocator, io: std.Io, args_json: []const u8) !ToolResult {
    _ = io;
    var parsed = std.json.parseFromSlice(TodosArgs, allocator, args_json, .{ .ignore_unknown_fields = true }) catch |err| {
        return .{
            .success = false,
            .output = try allocator.dupe(u8, ""),
            .error_message = try std.fmt.allocPrint(allocator, "JSON parse error in todos tool: {s}", .{@errorName(err)}),
        };
    };
    defer parsed.deinit();

    var output: std.ArrayList(u8) = .empty;
    defer output.deinit(allocator);

    if (std.mem.eql(u8, parsed.value.action, "add")) {
        const task = parsed.value.task orelse return .{
            .success = false,
            .output = try allocator.dupe(u8, ""),
            .error_message = try allocator.dupe(u8, "'task' parameter is required for 'add' action"),
        };

        const id = store.next_id;
        const task_copy = try allocator.dupe(u8, task);
        errdefer allocator.free(task_copy);
        try store.items.append(allocator, .{
            .id = id,
            .task = task_copy,
            .done = false,
        });
        store.next_id += 1;

        const msg = try std.fmt.allocPrint(allocator, "Added task #{d}: {s}", .{ id, task });
        defer allocator.free(msg);
        try output.appendSlice(allocator, msg);
    } else if (std.mem.eql(u8, parsed.value.action, "complete")) {
        const target_id = parsed.value.id orelse return .{
            .success = false,
            .output = try allocator.dupe(u8, ""),
            .error_message = try allocator.dupe(u8, "'id' parameter is required for 'complete' action"),
        };

        for (store.items.items) |*item| {
            if (item.id == target_id) {
                item.done = true;
                const msg = try std.fmt.allocPrint(allocator, "Marked task #{d} as completed: {s}", .{ item.id, item.task });
                defer allocator.free(msg);
                try output.appendSlice(allocator, msg);
                return .{ .success = true, .output = try output.toOwnedSlice(allocator) };
            }
        }

        return .{
            .success = false,
            .output = try allocator.dupe(u8, ""),
            .error_message = try std.fmt.allocPrint(allocator, "Task with ID #{d} not found", .{target_id}),
        };
    } else if (std.mem.eql(u8, parsed.value.action, "clear")) {
        store.clear(allocator);
        try output.appendSlice(allocator, "All tasks cleared.");
    } else if (std.mem.eql(u8, parsed.value.action, "list")) {
        if (store.items.items.len == 0) {
            try output.appendSlice(allocator, "No tasks in the plan.");
        } else {
            try output.appendSlice(allocator, "=== Current Task Plan ===\n");
            for (store.items.items) |item| {
                const line = try std.fmt.allocPrint(allocator, "{s} #{d}: {s}\n", .{
                    if (item.done) "[✔]" else "[ ]",
                    item.id,
                    item.task,
                });
                defer allocator.free(line);
                try output.appendSlice(allocator, line);
            }
        }
    } else {
        return .{
            .success = false,
            .output = try allocator.dupe(u8, ""),
            .error_message = try std.fmt.allocPrint(allocator, "Unsupported todos action '{s}'", .{parsed.value.action}),
        };
    }

    return .{ .success = true, .output = try output.toOwnedSlice(allocator) };
}

// Stateful tools must run through ToolRegistry, which owns the TodoStore.
pub fn execute(allocator: std.mem.Allocator, io: std.Io, args_json: []const u8) !ToolResult {
    _ = io;
    _ = args_json;
    return .{
        .success = false,
        .output = try allocator.dupe(u8, ""),
        .error_message = try allocator.dupe(u8, "todos requires a registry-owned TodoStore"),
    };
}

pub const tool_def = Tool{
    .name = "todos",
    .description = "Manage the current agent-owned task plan (actions: add, complete, list, clear).",
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

test "todo stores are isolated and lifecycle is explicit" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;

    var first = TodoStore.init();
    defer first.deinit(allocator);
    var second = TodoStore.init();
    defer second.deinit(allocator);

    var add = try executeWithStore(&first, allocator, io, "{\"action\":\"add\",\"task\":\"Build Zig 0.16 agent\"}");
    defer add.deinit(allocator);
    try std.testing.expect(add.success);

    var first_list = try executeWithStore(&first, allocator, io, "{\"action\":\"list\"}");
    defer first_list.deinit(allocator);
    try std.testing.expect(std.mem.indexOf(u8, first_list.output, "Build Zig 0.16 agent") != null);

    var second_list = try executeWithStore(&second, allocator, io, "{\"action\":\"list\"}");
    defer second_list.deinit(allocator);
    try std.testing.expectEqualStrings("No tasks in the plan.", second_list.output);
}
