const std = @import("std");
const prov = @import("provider.zig");
pub const CompletionRequest = prov.CompletionRequest;
pub const CompletionResponse = prov.CompletionResponse;
pub const ToolCall = prov.ToolCall;

pub const AnthropicProvider = struct {
    api_key: []const u8,

    pub fn init(api_key: []const u8) AnthropicProvider {
        return .{ .api_key = api_key };
    }

    pub fn send(self: AnthropicProvider, allocator: std.mem.Allocator, io: std.Io, request: CompletionRequest) !CompletionResponse {
        if (self.api_key.len == 0) {
            return error.MissingApiKey;
        }

        var client: std.http.Client = .{
            .allocator = allocator,
            .io = io,
        };
        defer client.deinit();

        const endpoint = "https://api.anthropic.com/v1/messages";
        const uri = try std.Uri.parse(endpoint);

        var payload_buf: std.ArrayList(u8) = .empty;
        defer payload_buf.deinit(allocator);

        try payload_buf.appendSlice(allocator, "{\"model\":");
        try std.json.stringify(request.model, .{}, payload_buf.writer(allocator));
        try payload_buf.appendSlice(allocator, ",\"max_tokens\":4096,\"messages\":[");

        var msg_count: usize = 0;
        for (request.messages) |msg| {
            if (msg.role == .system) continue; // Anthropic takes system prompt as top-level field
            if (msg_count > 0) try payload_buf.appendSlice(allocator, ",");
            try payload_buf.appendSlice(allocator, "{\"role\":\"");
            try payload_buf.appendSlice(allocator, msg.role.asString());
            try payload_buf.appendSlice(allocator, "\",\"content\":");
            try std.json.stringify(msg.content, .{}, payload_buf.writer(allocator));
            try payload_buf.appendSlice(allocator, "}");
            msg_count += 1;
        }
        try payload_buf.appendSlice(allocator, "]}");

        var header_buffer: [4096]u8 = undefined;
        var req = try client.open(.POST, uri, .{
            .server_header_buffer = &header_buffer,
            .headers = .{
                .content_type = .{ .override = "application/json" },
            },
        });
        defer req.deinit();

        req.transfer_encoding = .{ .content_length = payload_buf.items.len };
        try req.send();
        try req.writeAll(payload_buf.items);
        try req.finish();
        try req.wait();

        if (req.response.status != .ok) {
            return error.HttpError;
        }

        const body = try req.reader().readAllAlloc(allocator, 1024 * 1024);
        defer allocator.free(body);

        var parsed = try std.json.parseFromSlice(std.json.Value, allocator, body, .{});
        defer parsed.deinit();

        const content_array = parsed.value.object.get("content") orelse return error.InvalidResponse;
        if (content_array.array.items.len == 0) return error.EmptyContent;

        const first_block = content_array.array.items[0];
        const text_val = first_block.object.get("text") orelse return error.InvalidResponse;

        return CompletionResponse{
            .content = try allocator.dupe(u8, text_val.string),
            .tool_calls = null,
            .tokens_used = 200,
        };
    }
};
