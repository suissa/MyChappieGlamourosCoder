const std = @import("std");
const tool_mod = @import("tool.zig");
pub const Tool = tool_mod.Tool;
pub const ToolResult = tool_mod.ToolResult;

const store_dir = ".mychappie";
const store_path = ".mychappie/todos.ndjson";

pub const TodoItem = struct {
    id: usize,
    task: []u8,
    done: bool,
};

pub const TodoStore = struct {
    items: std.ArrayList(TodoItem) = .empty,
    next_id: usize = 1,

    pub fn deinit(self: *TodoStore, allocator: std.mem.Allocator) void {
        for (self.items.items) |item| allocator.free(item.task);
        self.items.deinit(allocator);
        self.* = undefined;
    }

    fn append(self: *TodoStore, allocator: std.mem.Allocator, task: []const u8) !usize {
        const id = self.next_id;
        const task_copy = try allocator.dupe(u8, task);
        errdefer allocator.free(task_copy);
        try self.items.append(allocator, .{ .id = id, .task = task_copy, .done = false });
        self.next_id += 1;
        return id;
    }
};

const DiskTodo = struct {
    id: usize,
    task: []const u8,
    done: bool,
};

const TodosArgs = struct {
    action: []const u8,
    task: ?[]const u8 = null,
    id: ?usize = null,
};

pub fn execute(allocator: std.mem.Allocator, io: std.Io, args_json: []const u8) !ToolResult {
    var parsed = std.json.parseFromSlice(TodosArgs, allocator, args_json, .{ .ignore_unknown_fields = true }) catch |err| {
        const msg = try std.fmt.allocPrint(allocator, "JSON parse error in todos tool: {s}", .{@errorName(err)});
        return .{ .success = false, .output = try allocator.dupe(u8, ""), .error_message = msg };
    };
    defer parsed.deinit();

    var store = loadStore(allocator, io) catch |err| {
        return .{
            .success = false,
            .output = try allocator.dupe(u8, ""),
            .error_message = try std.fmt.allocPrint(allocator, "Failed to load todo store: {s}", .{@errorName(err)}),
        };
    };
    defer store.deinit(allocator);

    const action = parsed.value.action;
    var out: std.Io.Writer.Allocating = .init(allocator);
    defer out.deinit();

    if (std.mem.eql(u8, action, "add")) {
        const task = parsed.value.task orelse {
            return .{
                .success = false,
                .output = try allocator.dupe(u8, ""),
                .error_message = try allocator.dupe(u8, "'task' parameter is required for 'add' action"),
            };
        };
        if (task.len == 0) {
            return .{
                .success = false,
                .output = try allocator.dupe(u8, ""),
                .error_message = try allocator.dupe(u8, "task cannot be empty"),
            };
        }

        const id = try store.append(allocator, task);
        try saveStore(&store, allocator, io);
        try out.writer.print("Added task #{d}: {s}", .{ id, task });
    } else if (std.mem.eql(u8, action, "complete")) {
        const target_id = parsed.value.id orelse {
            return .{
                .success = false,
                .output = try allocator.dupe(u8, ""),
                .error_message = try allocator.dupe(u8, "'id' parameter is required for 'complete' action"),
            };
        };

        var found = false;
        for (store.items.items) |*item| {
            if (item.id == target_id) {
                item.done = true;
                found = true;
                try out.writer.print("Marked task #{d} as completed: {s}", .{ item.id, item.task });
                break;
            }
        }
        if (!found) {
            return .{
                .success = false,
                .output = try allocator.dupe(u8, ""),
                .error_message = try std.fmt.allocPrint(allocator, "Task with ID #{d} not found", .{target_id}),
            };
        }
        try saveStore(&store, allocator, io);
    } else if (std.mem.eql(u8, action, "clear")) {
        for (store.items.items) |item| allocator.free(item.task);
        store.items.clearRetainingCapacity();
        store.next_id = 1;
        try saveStore(&store, allocator, io);
        try out.writer.writeAll("All tasks cleared.");
    } else if (std.mem.eql(u8, action, "list")) {
        if (store.items.items.len == 0) {
            try out.writer.writeAll("No tasks in the plan.");
        } else {
            try out.writer.writeAll("=== Current Task Plan ===\n");
            for (store.items.items) |item| {
                try out.writer.print("{s} #{d}: {s}\n", .{ if (item.done) "[x]" else "[ ]", item.id, item.task });
            }
        }
    } else {
        return .{
            .success = false,
            .output = try allocator.dupe(u8, ""),
            .error_message = try std.fmt.allocPrint(allocator, "Unknown todos action: {s}", .{action}),
        };
    }

    return .{ .success = true, .output = try out.toOwnedSlice() };
}

fn loadStore(allocator: std.mem.Allocator, io: std.Io) !TodoStore {
    var store: TodoStore = .{};
    errdefer store.deinit(allocator);

    const cwd = std.Io.Dir.cwd();
    const content = cwd.readFileAlloc(io, store_path, allocator, .unlimited) catch |err| switch (err) {
        error.FileNotFound => return store,
        else => return err,
    };
    defer allocator.free(content);

    var lines = std.mem.splitScalar(u8, content, '\n');
    while (lines.next()) |line| {
        if (line.len == 0) continue;
        var parsed = try std.json.parseFromSlice(DiskTodo, allocator, line, .{ .ignore_unknown_fields = true });
        defer parsed.deinit();

        const task_copy = try allocator.dupe(u8, parsed.value.task);
        errdefer allocator.free(task_copy);
        try store.items.append(allocator, .{
            .id = parsed.value.id,
            .task = task_copy,
            .done = parsed.value.done,
        });
        if (parsed.value.id >= store.next_id) store.next_id = parsed.value.id + 1;
    }

    return store;
}

fn saveStore(store: *const TodoStore, allocator: std.mem.Allocator, io: std.Io) !void {
    var out: std.Io.Writer.Allocating = .init(allocator);
    defer out.deinit();

    for (store.items.items) |item| {
        var jw: std.json.Stringify = .{ .writer = &out.writer };
        try jw.write(DiskTodo{ .id = item.id, .task = item.task, .done = item.done });
        try out.writer.writeByte('\n');
    }

    const cwd = std.Io.Dir.cwd();
    try cwd.createDirPath(io, store_dir);
    try cwd.writeFile(io, .{ .sub_path = store_path, .data = out.written() });
}

pub const tool_def = Tool{
    .name = "todos",
    .description = "Manage the workspace-local autonomous task plan. State is persisted in .mychappie/todos.ndjson rather than global process memory.",
    .parameters_json =
    \\{
    \\  "type": "object",
    \\  "properties": {
    \\    "action": { "type": "string", "enum": ["add", "complete", "list", "clear"] },
    \\    "task": { "type": "string", "description": "Task description (when action is add)" },
    \\    "id": { "type": "integer", "description": "Task ID (when action is complete)" }
    \\  },
    \\  "required": ["action"]
    \\}
    ,
    .execute_fn = execute,
};

test "todo store owns state instead of using global mutable memory" {
    const allocator = std.testing.allocator;
    var store: TodoStore = .{};
    defer store.deinit(allocator);

    const first = try store.append(allocator, "Build Zig 0.16 agent");
    const second = try store.append(allocator, "Validate providers");
    try std.testing.expectEqual(@as(usize, 1), first);
    try std.testing.expectEqual(@as(usize, 2), second);
    try std.testing.expectEqual(@as(usize, 2), store.items.items.len);
}
