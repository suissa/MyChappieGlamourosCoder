const std = @import("std");

pub const glamour = @import("glamour.zig");
pub const Glamour = glamour.Glamour;

pub const tools = struct {
    pub const tool = @import("tools/tool.zig");
    pub const Tool = tool.Tool;
    pub const ToolResult = tool.ToolResult;

    pub const view = @import("tools/view.zig");
    pub const write = @import("tools/write.zig");
    pub const edit = @import("tools/edit.zig");
    pub const bash = @import("tools/bash.zig");
    pub const grep = @import("tools/grep.zig");
    pub const glob = @import("tools/glob.zig");
    pub const todos = @import("tools/todos.zig");
    pub const question = @import("tools/question.zig");
    pub const registry = @import("tools/registry.zig");
    pub const ToolRegistry = registry.ToolRegistry;
};

pub const llm = struct {
    pub const provider = @import("llm/provider.zig");
    pub const mock = @import("llm/mock.zig");
    pub const http_transport = @import("llm/http_transport.zig");
    pub const runtime_provider = @import("llm/runtime_provider.zig");
    pub const RuntimeProvider = runtime_provider.RuntimeProvider;
    pub const gemini = @import("llm/gemini.zig");
    pub const openai = @import("llm/openai.zig");
    pub const anthropic = @import("llm/anthropic.zig");
    pub const ollama = @import("llm/ollama.zig");
};

pub const agent = struct {
    pub const session = @import("agent/session.zig");
    pub const Session = session.Session;

    pub const prompts = @import("agent/prompts.zig");
    pub const Prompts = prompts.Prompts;

    pub const coordinator = @import("agent/coordinator.zig");
    pub const Coordinator = coordinator.Coordinator;

    pub const agent_impl = @import("agent/agent.zig");
    pub const CoderAgent = agent_impl.CoderAgent;
};

pub const permission = @import("permission/permission.zig");
pub const PermissionManager = permission.PermissionManager;

pub const config = @import("config.zig");
pub const AppConfig = config.AppConfig;

test {
    std.testing.refAllDecls(@This());
    _ = @import("glamour.zig");
    _ = @import("tools/tool.zig");
    _ = @import("tools/view.zig");
    _ = @import("tools/write.zig");
    _ = @import("tools/edit.zig");
    _ = @import("tools/bash.zig");
    _ = @import("tools/grep.zig");
    _ = @import("tools/glob.zig");
    _ = @import("tools/todos.zig");
    _ = @import("tools/question.zig");
    _ = @import("tools/registry.zig");
    _ = @import("llm/provider.zig");
    _ = @import("llm/mock.zig");
    _ = @import("llm/http_transport.zig");
    _ = @import("llm/runtime_provider.zig");
    _ = @import("llm/gemini.zig");
    _ = @import("llm/openai.zig");
    _ = @import("llm/anthropic.zig");
    _ = @import("llm/ollama.zig");
    _ = @import("agent/session.zig");
    _ = @import("agent/prompts.zig");
    _ = @import("agent/coordinator.zig");
    _ = @import("agent/agent.zig");
    _ = @import("permission/permission.zig");
    _ = @import("config.zig");
}
