const std = @import("std");
const prompts = @import("prompts.zig").Prompts;

pub const AgentRole = enum {
    coder,
    architect,
    reviewer,

    pub fn asString(self: AgentRole) []const u8 {
        return switch (self) {
            .coder => "coder",
            .architect => "architect",
            .reviewer => "reviewer",
        };
    }

    pub fn prompt(self: AgentRole) []const u8 {
        return switch (self) {
            .coder => prompts.CODER_PROMPT,
            .architect => prompts.ARCHITECT_PROMPT,
            .reviewer => prompts.REVIEWER_PROMPT,
        };
    }
};

pub const Coordinator = struct {
    active_role: AgentRole = .coder,

    pub fn init(role: ?AgentRole) Coordinator {
        return .{
            .active_role = role orelse .coder,
        };
    }

    pub fn setRole(self: *Coordinator, role: AgentRole) void {
        self.active_role = role;
    }

    pub fn getCombinedPrompt(self: Coordinator, allocator: std.mem.Allocator) ![]const u8 {
        return try std.fmt.allocPrint(
            allocator,
            "{s}\n\n[Active Role: {s}]\n{s}",
            .{ prompts.DEFAULT_SYSTEM_PROMPT, self.active_role.asString(), self.active_role.prompt() },
        );
    }
};

test "coordinator prompt composition" {
    const allocator = std.testing.allocator;
    var coord = Coordinator.init(.coder);
    const p = try coord.getCombinedPrompt(allocator);
    defer allocator.free(p);

    try std.testing.expect(std.mem.indexOf(u8, p, "Coder Agent") != null);
}
