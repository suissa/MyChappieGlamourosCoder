const std = @import("std");

pub const ToolResult = struct {
    success: bool,
    output: []const u8,
    error_message: ?[]const u8 = null,

    pub fn deinit(self: *ToolResult, allocator: std.mem.Allocator) void {
        allocator.free(self.output);
        if (self.error_message) |msg| {
            allocator.free(msg);
        }
        self.* = undefined;
    }
};

pub const Tool = struct {
    name: []const u8,
    description: []const u8,
    parameters_json: []const u8,
    execute_fn: *const fn (allocator: std.mem.Allocator, io: std.Io, args_json: []const u8) anyerror!ToolResult,

    pub fn execute(self: Tool, allocator: std.mem.Allocator, io: std.Io, args_json: []const u8) !ToolResult {
        return self.execute_fn(allocator, io, args_json);
    }
};

test "tool result deinit" {
    const allocator = std.testing.allocator;
    const out = try allocator.dupe(u8, "success output");
    var res = ToolResult{
        .success = true,
        .output = out,
    };
    defer res.deinit(allocator);
    try std.testing.expectEqualStrings("success output", res.output);
}
