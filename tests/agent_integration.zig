const std = @import("std");
const mychappie = @import("mychappie_coder");

test "coder agent autonomous execution with write tool" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;
    const cwd = std.Io.Dir.cwd();

    defer cwd.deleteFile(io, "chappie_demo.txt") catch {};

    var agent = try mychappie.agent.CoderAgent.init(allocator, ".", .{ .max_steps = 5 });
    defer agent.deinit(allocator);

    const final_output = try agent.executeTurn(
        allocator,
        io,
        "Crie um arquivo teste.txt com conteúdo de demonstração",
    );
    defer allocator.free(final_output);

    try std.testing.expect(final_output.len > 0);

    const created_content = try cwd.readFileAlloc(io, "chappie_demo.txt", allocator, .unlimited);
    defer allocator.free(created_content);

    try std.testing.expect(std.mem.indexOf(u8, created_content, "MyChappie Glamouros Coder") != null);
}
