const std = @import("std");
const prov = @import("provider.zig");
pub const CompletionRequest = prov.CompletionRequest;
pub const CompletionResponse = prov.CompletionResponse;
pub const ToolCall = prov.ToolCall;

pub const GeminiProvider = struct {
    api_key: []const u8,

    pub fn init(api_key: []const u8) GeminiProvider {
        return .{ .api_key = api_key };
    }

    pub fn send(self: GeminiProvider, allocator: std.mem.Allocator, io: std.Io, request: CompletionRequest) !CompletionResponse {
        if (self.api_key.len == 0) {
            return error.MissingApiKey;
        }

        var client: std.http.Client = .{
            .allocator = allocator,
            .io = io,
        };
        defer client.deinit();

        const endpoint = try std.fmt.allocPrint(
            allocator,
            "https://generativelanguage.googleapis.com/v1beta/models/{s}:generateContent?key={s}",
            .{ request.model, self.api_key },
        );
        defer allocator.free(endpoint);

        const uri = try std.Uri.parse(endpoint);

        // Build simplified JSON payload
        var payload_buf: std.ArrayList(u8) = .empty;
        defer payload_buf.deinit(allocator);

        try payload_buf.appendSlice(allocator, "{\"contents\":[");
        for (request.messages, 0..) |msg, idx| {
            if (idx > 0) try payload_buf.appendSlice(allocator, ",");
            const role_str = if (msg.role == .user or msg.role == .system) "user" else "model";
            try payload_buf.appendSlice(allocator, "{\"role\":\"");
            try payload_buf.appendSlice(allocator, role_str);
            try payload_buf.appendSlice(allocator, "\",\"parts\":[{\"text\":");
            try std.json.stringify(msg.content, .{}, payload_buf.writer(allocator));
            try payload_buf.appendSlice(allocator, "}]}");
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
            const err_body = try req.reader().readAllAlloc(allocator, 8192);
            defer allocator.free(err_body);
            return error.HttpError;
        }

        const body = try req.reader().readAllAlloc(allocator, 1024 * 1024);
        defer allocator.free(body);

        var parsed = try std.json.parseFromSlice(std.json.Value, allocator, body, .{});
        defer parsed.deinit();

        // Extract response text
        const candidates = parsed.value.object.get("candidates") orelse return error.InvalidResponse;
        if (candidates.array.items.len == 0) return error.EmptyCandidates;

        const first_cand = candidates.array.items[0];
        const content_obj = first_cand.object.get("content") orelse return error.InvalidResponse;
        const parts = content_obj.object.get("parts") orelse return error.InvalidResponse;

        var text_acc: std.ArrayList(u8) = .empty;
        defer text_acc.deinit(allocator);

        for (parts.array.items) |part| {
            if (part.object.get("text")) |t| {
                try text_acc.appendSlice(allocator, t.string);
            }
        }

        return CompletionResponse{
            .content = try text_acc.toOwnedSlice(allocator),
            .tool_calls = null,
            .tokens_used = 100,
        };
    }
};
