const std = @import("std");

pub const max_response_body_bytes: usize = 1024 * 1024;

pub const Response = struct {
    status: std.http.Status,
    body: []u8,

    pub fn deinit(self: *Response, allocator: std.mem.Allocator) void {
        allocator.free(self.body);
        self.* = undefined;
    }
};

/// Sends one JSON POST using the Zig 0.16 std.http.Client API.
///
/// Security properties:
/// - redirects are rejected so credentials cannot cross origins;
/// - provider credentials belong in `privileged_headers`;
/// - response compression is disabled to keep body accounting deterministic;
/// - response bodies are bounded to 1 MiB.
pub fn postJson(
    allocator: std.mem.Allocator,
    io: std.Io,
    url: []const u8,
    body: []const u8,
    extra_headers: []const std.http.Header,
    privileged_headers: []const std.http.Header,
) !Response {
    var client: std.http.Client = .{
        .allocator = allocator,
        .io = io,
    };
    defer client.deinit();

    const uri = try std.Uri.parse(url);

    var request = try client.request(.POST, uri, .{
        .keep_alive = false,
        .redirect_behavior = .not_allowed,
        .headers = .{
            .content_type = .{ .override = "application/json" },
            .accept_encoding = .{ .override = "identity" },
        },
        .extra_headers = extra_headers,
        .privileged_headers = privileged_headers,
    });
    defer request.deinit();

    try request.sendBodyComplete(body);

    var redirect_buffer: [8 * 1024]u8 = undefined;
    var response = try request.receiveHead(&redirect_buffer);
    const status = response.head.status;

    if (response.head.content_length) |content_length| {
        if (content_length > max_response_body_bytes) return error.ResponseTooLarge;
    }

    var transfer_buffer: [8 * 1024]u8 = undefined;
    const reader = response.reader(&transfer_buffer);

    var output: std.ArrayList(u8) = .empty;
    errdefer output.deinit(allocator);

    var chunk: [8 * 1024]u8 = undefined;
    while (true) {
        const bytes_read = reader.readSliceShort(&chunk) catch return error.ResponseReadFailed;
        if (bytes_read == 0) break;

        if (output.items.len > max_response_body_bytes - bytes_read) {
            return error.ResponseTooLarge;
        }
        try output.appendSlice(allocator, chunk[0..bytes_read]);
    }

    return .{
        .status = status,
        .body = try output.toOwnedSlice(allocator),
    };
}

test "transport response limit is explicit" {
    try std.testing.expectEqual(@as(usize, 1024 * 1024), max_response_body_bytes);
}
