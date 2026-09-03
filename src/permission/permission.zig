const std = @import("std");

pub const PermissionLevel = enum {
    safe,
    cautious,
    dangerous,
};

pub const PermissionManager = struct {
    skip_all: bool = false,

    pub fn init(skip_all: bool) PermissionManager {
        return .{ .skip_all = skip_all };
    }

    pub fn classifyTool(self: PermissionManager, tool_name: []const u8) PermissionLevel {
        _ = self;
        if (std.mem.eql(u8, tool_name, "view") or
            std.mem.eql(u8, tool_name, "grep") or
            std.mem.eql(u8, tool_name, "glob") or
            std.mem.eql(u8, tool_name, "todos") or
            std.mem.eql(u8, tool_name, "question"))
        {
            return .safe;
        }

        if (std.mem.eql(u8, tool_name, "write") or
            std.mem.eql(u8, tool_name, "edit"))
        {
            return .cautious;
        }

        return .dangerous; // bash, process kills, system operations
    }

    pub fn isAllowed(self: PermissionManager, tool_name: []const u8) bool {
        if (self.skip_all) return true;
        const level = self.classifyTool(tool_name);
        return level == .safe or level == .cautious;
    }
};

test "permission manager classification" {
    const pm = PermissionManager.init(false);
    try std.testing.expect(pm.classifyTool("view") == .safe);
    try std.testing.expect(pm.classifyTool("write") == .cautious);
    try std.testing.expect(pm.classifyTool("bash") == .dangerous);
    try std.testing.expect(pm.isAllowed("view"));
    try std.testing.expect(!pm.isAllowed("bash"));

    const permissive_pm = PermissionManager.init(true);
    try std.testing.expect(permissive_pm.isAllowed("bash"));
}
