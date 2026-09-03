const std = @import("std");
const mychappie = @import("mychappie_coder");
const Glamour = mychappie.Glamour;

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const io = init.io;
    const args = try init.minimal.args.toSlice(init.arena.allocator());

    if (args.len < 2) {
        Glamour.printBanner();
        printHelp();
        return;
    }

    const command = args[1];

    if (std.mem.eql(u8, command, "version") or std.mem.eql(u8, command, "-v") or std.mem.eql(u8, command, "--version")) {
        Glamour.printBanner();
        std.debug.print("  {s}Version:{s}   0.1.0-alpha (Zig v0.16.0 Native)\n", .{ Glamour.Theme.cyan, Glamour.Theme.reset });
        std.debug.print("  {s}Plane:{s}     Agents / Coder Plane\n", .{ Glamour.Theme.purple, Glamour.Theme.reset });
        std.debug.print("  {s}Engine:{s}    SOTA-DD Autonomous Loop with Multi-Tool Pipeline\n", .{ Glamour.Theme.green, Glamour.Theme.reset });
        std.debug.print("  {s}Runtime:{s}   std.Io + runtime-dispatched LLM providers\n\n", .{ Glamour.Theme.slate, Glamour.Theme.reset });
        return;
    }

    if (std.mem.eql(u8, command, "tools")) {
        Glamour.printBanner();
        std.debug.print("{s}📦 FERRAMENTAS DO AGENTE DISPONÍVEIS:{s}\n\n", .{ Glamour.Theme.yellow, Glamour.Theme.reset });

        var registry = mychappie.tools.ToolRegistry.init();
        defer registry.deinit(allocator);
        for (registry.tools) |tool| {
            std.debug.print("  {s}⚡ {s:<12}{s} {s}\n", .{
                Glamour.Theme.cyan,
                tool.name,
                Glamour.Theme.reset,
                tool.description,
            });
        }
        std.debug.print("\n", .{});
        return;
    }

    if (std.mem.eql(u8, command, "models")) {
        Glamour.printBanner();
        std.debug.print("{s}🧠 PROVEDORES DE LLM SUPORTADOS:{s}\n\n", .{ Glamour.Theme.purple, Glamour.Theme.reset });
        std.debug.print("  • {s}Google Gemini{s}         via GEMINI_API_KEY\n", .{ Glamour.Theme.cyan, Glamour.Theme.reset });
        std.debug.print("  • {s}OpenAI / Compatible{s}   via OPENAI_API_KEY + OPENAI_BASE_URL opcional\n", .{ Glamour.Theme.green, Glamour.Theme.reset });
        std.debug.print("  • {s}Anthropic Claude{s}      via ANTHROPIC_API_KEY\n", .{ Glamour.Theme.orange, Glamour.Theme.reset });
        std.debug.print("  • {s}Ollama Local{s}          via OLLAMA_HOST + OLLAMA_MODEL opcional\n", .{ Glamour.Theme.slate, Glamour.Theme.reset });
        std.debug.print("  • {s}Deterministic Mock{s}    fallback offline para testes\n\n", .{ Glamour.Theme.yellow, Glamour.Theme.reset });
        std.debug.print("  MYCHAPPIE_MODEL sobrescreve o modelo detectado para qualquer provider.\n\n", .{});
        return;
    }

    if (std.mem.eql(u8, command, "info")) {
        Glamour.printBanner();
        const app_cfg = mychappie.AppConfig.load(io, ".", init.environ_map);
        std.debug.print("{s}📊 DIAGNÓSTICO DO AMBIENTE:{s}\n", .{ Glamour.Theme.cyan, Glamour.Theme.reset });
        std.debug.print("  - Workspace:        {s}\n", .{app_cfg.workspace_root});
        std.debug.print("  - AGENTS.md:        {s}\n", .{if (app_cfg.has_agents_md) "Encontrado ✔" else "Não encontrado (usando padrão)"});
        std.debug.print("  - Active Provider:  {s}\n", .{@tagName(app_cfg.provider_type)});
        std.debug.print("  - Active Model:     {s}\n", .{app_cfg.model});
        if (app_cfg.base_url) |base_url| {
            std.debug.print("  - Provider URL:     {s}\n", .{base_url});
        }
        std.debug.print("\n", .{});
        return;
    }

    if (std.mem.eql(u8, command, "run")) {
        var skip_permissions = false;
        var prompt_index: usize = 2;

        if (args.len > 2 and std.mem.eql(u8, args[2], "--dangerously-skip-permissions")) {
            skip_permissions = true;
            prompt_index = 3;
        }

        if (args.len <= prompt_index) {
            std.debug.print("{s}Erro:{s} Forneça um prompt. Exemplo: mychappie-coder run \"Crie um arquivo teste.txt\"\n", .{ Glamour.Theme.red, Glamour.Theme.reset });
            return;
        }

        const app_cfg = mychappie.AppConfig.load(io, ".", init.environ_map);
        try runAgent(allocator, io, app_cfg, args[prompt_index], skip_permissions);
        return;
    }

    if (std.mem.eql(u8, command, "help") or std.mem.eql(u8, command, "--help") or std.mem.eql(u8, command, "-h")) {
        Glamour.printBanner();
        printHelp();
        return;
    }

    // Direct prompts are safe by default. Dangerous tools require the explicit run flag.
    const app_cfg = mychappie.AppConfig.load(io, ".", init.environ_map);
    try runAgent(allocator, io, app_cfg, command, false);
}

fn runAgent(
    allocator: std.mem.Allocator,
    io: std.Io,
    app_cfg: mychappie.AppConfig,
    prompt: []const u8,
    skip_permissions: bool,
) !void {
    Glamour.printBanner();
    std.debug.print("{s}🎯 OBJETIVO:{s} {s}\n", .{ Glamour.Theme.yellow, Glamour.Theme.reset, prompt });
    std.debug.print("{s}🧠 PROVIDER:{s} {s} / {s}\n", .{
        Glamour.Theme.purple,
        Glamour.Theme.reset,
        @tagName(app_cfg.provider_type),
        app_cfg.model,
    });
    std.debug.print("{s}🔐 PERMISSÕES:{s} {s}\n\n", .{
        Glamour.Theme.cyan,
        Glamour.Theme.reset,
        if (skip_permissions) "BYPASS EXPLÍCITO (dangerous tools habilitadas)" else "SAFE DEFAULT (dangerous tools bloqueadas)",
    });

    var coder = try mychappie.agent.CoderAgent.initWithConfig(allocator, app_cfg, .{
        .max_steps = 10,
        .dangerously_skip_permissions = skip_permissions,
    });
    defer coder.deinit(allocator);

    const result = try coder.executeTurn(allocator, io, prompt);
    defer allocator.free(result);

    std.debug.print("\n", .{});
    try Glamour.printBox(allocator, "RESPOSTA DO AGENTE", result, Glamour.Theme.green);
    std.debug.print("\n", .{});
}

fn printHelp() void {
    std.debug.print("{s}USO:{s}\n", .{ Glamour.Theme.bold, Glamour.Theme.reset });
    std.debug.print("  mychappie-coder <comando> [argumentos]\n\n", .{});
    std.debug.print("{s}COMANDOS:{s}\n", .{ Glamour.Theme.bold, Glamour.Theme.reset });
    std.debug.print("  {s}run <prompt>{s}                              Executa com provider detectado e permissões seguras\n", .{ Glamour.Theme.cyan, Glamour.Theme.reset });
    std.debug.print("  {s}run --dangerously-skip-permissions <prompt>{s} Habilita explicitamente tools perigosas\n", .{ Glamour.Theme.red, Glamour.Theme.reset });
    std.debug.print("  {s}tools{s}                                     Exibe o catálogo de ferramentas disponíveis\n", .{ Glamour.Theme.cyan, Glamour.Theme.reset });
    std.debug.print("  {s}models{s}                                    Exibe providers e variáveis de configuração\n", .{ Glamour.Theme.cyan, Glamour.Theme.reset });
    std.debug.print("  {s}info{s}                                      Exibe provider/modelo realmente detectados\n", .{ Glamour.Theme.cyan, Glamour.Theme.reset });
    std.debug.print("  {s}version{s}                                   Exibe informações de versão e compilação Zig v0.16\n", .{ Glamour.Theme.cyan, Glamour.Theme.reset });
    std.debug.print("  {s}help{s}                                      Exibe esta mensagem de ajuda\n\n", .{ Glamour.Theme.cyan, Glamour.Theme.reset });
}
