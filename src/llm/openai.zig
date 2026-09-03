const std = @import("std");
const prov = @import("provider.zig");
pub const CompletionRequest = prov.CompletionRequest;
pub const CompletionResponse = prov.CompletionResponse;
pub const ToolCall = prov.ToolCall;

pub const OpenAIProvider = struct {
    api_key: []const u8,
    base_url: []const u8 = "https://api.openai.com/v1",

    pub fn init(api_key: []const u8, base_url: ?[]const u8) OpenAIProvider {
        return .{
            .api_key = api_key,
            .base_url = base_url orelse "https://api.openai.com/v1",
        };
    }

    pub fn send(self: OpenAIProvider, allocator: std.mem.Allocator, io: std.Io, request: CompletionRequest) !CompletionResponse {
        if (self.api_key.len == 0) {
            return error.MissingApiKey;
        }

        var client: std.http.Client = .{
            .allocator = allocator,
            .io = io,
        };
        defer client.deinit();

        const endpoint = try std.fmt.allocPrint(allocator, "{s}/chat/completions", .{self.base_url});
        defer allocator.free(endpoint);

        const uri = try std.Uri.parse(endpoint);

        var payload_buf: std.ArrayList(u8) = .empty;
        defer payload_buf.deinit(allocator);

        try payload_buf.appendSlice(allocator, "{\"model\":");
        try std.json.stringify(request.model, .{}, payload_buf.writer(allocator));
        try payload_buf.appendSlice(allocator, ",\"messages\":[");

        for (request.messages, 0..) |msg, idx| {
            if (idx > 0) try payload_buf.appendSlice(allocator, ",");
            try payload_buf.appendSlice(allocator, "{\"role\":\"");
            try payload_buf.appendSlice(allocator, msg.role.asString());
            try payload_buf.appendSlice(allocator, "\",\"content\":");
            try std.json.stringify(msg.content, .{}, payload_buf.writer(allocator));
            try payload_buf.appendSlice(allocator, "}");
        }
        try payload_buf.appendSlice(allocator, "]}");

        const auth_header = try std.fmt.allocPrint(allocator, "Bearer {s}", .{self.api_key});
        defer allocator.free(auth_header);

        var header_buffer: [4096]u8 = undefined;
        var req = try client.open(.POST, uri, .{
            .server_header_buffer = &header_buffer,
            .headers = .{
                .content_type = .{ .override = "application/json" },
                .authorization = .{ .override = auth_header },
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

        const choices = parsed.value.object.get("choices") orelse return error.InvalidResponse;
        if (choices.array.items.len == 0) return error.EmptyChoices;

        const first_choice = choices.array.items[0];
        const message_obj = first_choice.object.get("message") orelse return error.InvalidResponse;
        const content_val = message_obj.object.get("content") orelse return error.InvalidResponse;

        return CompletionResponse{
            .content = try allocator.dupe(u8, content_val.string),
            .tool_calls = null,
            .tokens_used = 150,
        };
    }
};
