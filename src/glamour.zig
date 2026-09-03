const std = @import("std");

/// Sistema de Estilização e Temas Glamour para o Terminal
pub const Glamour = struct {
    // Paleta de Cores TrueColor ANSI (24-bit)
    pub const Theme = struct {
        pub const reset = "\x1b[0m";
        pub const bold = "\x1b[1m";
        pub const dim = "\x1b[2m";
        pub const italic = "\x1b[3m";
        pub const underline = "\x1b[4m";
        pub const inverse = "\x1b[7m";

        // Cores vibrantes neon & pastel
        pub const cyan = "\x1b[38;2;56;189;248m";
        pub const purple = "\x1b[38;2;192;132;252m";
        pub const green = "\x1b[38;2;74;222;128m";
        pub const yellow = "\x1b[38;2;250;204;21m";
        pub const red = "\x1b[38;2;248;113;113m";
        pub const orange = "\x1b[38;2;251;146;60m";
        pub const slate = "\x1b[38;2;148;163;184m";
        pub const dark_slate = "\x1b[38;2;71;85;105m";
        pub const white = "\x1b[38;2;248;250;252m";
        pub const bg_dark = "\x1b[48;2;15;23;42m";
        pub const bg_cyan = "\x1b[48;2;14;116;144m";
        pub const bg_purple = "\x1b[48;2;126;34;206m";
    };

    pub const spinner_frames = [_][]const u8{
        "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏",
    };

    pub fn printBanner() void {
        std.debug.print("\n", .{});
        std.debug.print("{s}{s}╔════════════════════════════════════════════════════════════════════════════╗{s}\n", .{ Theme.purple, Theme.bold, Theme.reset });
        std.debug.print("{s}{s}║   ⚡ MYCHAPPIE GLAMOUROS CODER — Native Zig v0.16 Autonomous Agent       ║{s}\n", .{ Theme.cyan, Theme.bold, Theme.reset });
        std.debug.print("{s}{s}║   AllasCode Semantic Planes • SOTA-DD • High-Performance AI Assistant     ║{s}\n", .{ Theme.slate, Theme.dim, Theme.reset });
        std.debug.print("{s}{s}╚════════════════════════════════════════════════════════════════════════════╝{s}\n\n", .{ Theme.purple, Theme.bold, Theme.reset });
    }

    pub fn printBadge(label: []const u8, color: []const u8) void {
        std.debug.print("{s}{s}[{s}]{s} ", .{ color, Theme.bold, label, Theme.reset });
    }

    pub fn printStatus(status: []const u8, message: []const u8) void {
        std.debug.print("{s}●{s} {s}{s}{s}: {s}\n", .{
            Theme.cyan,
            Theme.reset,
            Theme.bold,
            status,
            Theme.reset,
            message,
        });
    }

    pub fn printToolCall(tool_name: []const u8, params_summary: []const u8) void {
        std.debug.print("  {s}🔧 {s}[TOOL: {s}]{s} {s}{s}{s}\n", .{
            Theme.yellow,
            Theme.bold,
            tool_name,
            Theme.reset,
            Theme.slate,
            params_summary,
            Theme.reset,
        });
    }

    pub fn printToolResult(tool_name: []const u8, success: bool, preview: []const u8) void {
        const icon = if (success) "✔" else "✖";
        const color = if (success) Theme.green else Theme.red;
        std.debug.print("  {s}{s} [{s}]{s} {s}\n", .{
            color,
            icon,
            tool_name,
            Theme.reset,
            preview,
        });
    }

    pub fn printBox(allocator: std.mem.Allocator, title: []const u8, body: []const u8, border_color: []const u8) !void {
        _ = allocator;
        const width: usize = 76;
        std.debug.print("{s}╭─ {s}{s} {s}", .{ border_color, Theme.bold, title, border_color });

        const title_len: usize = title.len + 5;
        if (title_len < width) {
            var i: usize = title_len;
            while (i < width) : (i += 1) {
                std.debug.print("─", .{});
            }
        }
        std.debug.print("╮{s}\n", .{Theme.reset});

        var lines = std.mem.splitScalar(u8, body, '\n');
        while (lines.next()) |line| {
            std.debug.print("{s}│{s} {s}\n", .{ border_color, Theme.reset, line });
        }

        std.debug.print("{s}╰", .{border_color});
        var i: usize = 1;
        while (i < width) : (i += 1) {
            std.debug.print("─", .{});
        }
        std.debug.print("╯{s}\n", .{Theme.reset});
    }

    pub fn printDiff(diff_text: []const u8) void {
        var lines = std.mem.splitScalar(u8, diff_text, '\n');
        while (lines.next()) |line| {
            if (line.len == 0) {
                std.debug.print("\n", .{});
                continue;
            }
            if (line[0] == '+') {
                std.debug.print("{s}{s}{s}\n", .{ Theme.green, line, Theme.reset });
            } else if (line[0] == '-') {
                std.debug.print("{s}{s}{s}\n", .{ Theme.red, line, Theme.reset });
            } else if (line[0] == '@') {
                std.debug.print("{s}{s}{s}\n", .{ Theme.cyan, line, Theme.reset });
            } else {
                std.debug.print("  {s}{s}\n", .{ Theme.dim, line });
            }
        }
    }
};

test "glamour theme constants" {
    try std.testing.expect(Glamour.Theme.cyan.len > 0);
    try std.testing.expect(Glamour.Theme.reset.len > 0);
    try std.testing.expect(Glamour.spinner_frames.len == 10);
}
