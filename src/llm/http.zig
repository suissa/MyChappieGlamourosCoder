const std = @import("std");

/// Zig 0.16 HTTP transport used by every cloud/local LLM adapter.
/// The caller owns the returned response body.
pub fn postJson(
    allocator: std.mem.Allocator,
    io: std.Io,
    endpoint: []const u8,
    payload: []const u8,
    extra_headers: []const std.http.Header,
) ![]u8 {
    var client: std.http.Client = .{
        .allocator = allocator,
        .io = io,
    };
    defer client.deinit();

    var response: std.Io.Writer.Allocating = .init(allocator);
    errdefer response.deinit();

    const result = try client.fetch(.{
        .location = .{ .url = endpoint },
        .method = .POST,
        .payload = payload,
        .response_writer = &response.writer,
        .headers = .{
            .content_type = .{ .override = "application/json" },
            .accept_encoding = .{ .override = "identity" },
            .user_agent = .{ .override = "MyChappieGlamourosCoder/0.1 Zig/0.16" },
        },
        .extra_headers = extra_headers,
    });

    const status_code = @intFromEnum(result.status);
    if (status_code < 200 or status_code >= 300) {
        response.deinit();
        return error.HttpError;
    }

    return response.toOwnedSlice();
}

test "HTTP transport declaration is analyzable" {
    // Network calls intentionally do not run in the deterministic test suite.
    // Referencing the function forces Zig to analyze its 0.16 std.http surface.
    _ = postJson;
}
