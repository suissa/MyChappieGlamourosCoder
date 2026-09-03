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
        std.debug.print("  {s}Runtime:{s}   explicit std.process.Init + std.Io\n\n", .{ Glamour.Theme.slate, Glamour.Theme.reset });
        return;
    }

    if (std.mem.eql(u8, command, "tools")) {
        Glamour.printBanner();
        std.debug.print("{s}📦 FERRAMENTAS DO AGENTE DISPONÍVEIS:{s}\n\n", .{ Glamour.Theme.yellow, Glamour.Theme.reset });

        const reg = mychappie.tools.ToolRegistry.init();
        for (reg.tools) |t| {
            std.debug.print("  {s}⚡ {s:<12}{s} {s}\n", .{
                Glamour.Theme.cyan,
                t.name,
                Glamour.Theme.reset,
                t.description,
            });
        }
        std.debug.print("\n", .{});
        return;
    }

    if (std.mem.eql(u8, command, "models")) {
        Glamour.printBanner();
        std.debug.print("{s}🧠 PROVEDORES DE LLM SUPORTADOS:{s}\n\n", .{ Glamour.Theme.purple, Glamour.Theme.reset });
        std.debug.print("  • {s}Google Gemini{s}        via GEMINI_API_KEY\n", .{ Glamour.Theme.cyan, Glamour.Theme.reset });
        std.debug.print("  • {s}OpenAI / Compatible{s}  via OPENAI_API_KEY + OPENAI_BASE_URL opcional\n", .{ Glamour.Theme.green, Glamour.Theme.reset });
        std.debug.print("  • {s}Anthropic Claude{s}      via ANTHROPIC_API_KEY\n", .{ Glamour.Theme.orange, Glamour.Theme.reset });
        std.debug.print("  • {s}Ollama Local{s}          via OLLAMA_HOST\n", .{ Glamour.Theme.slate, Glamour.Theme.reset });
        std.debug.print("  • {s}Deterministic Mock{s}    offline verification and testing\n\n", .{ Glamour.Theme.yellow, Glamour.Theme.reset });
        std.debug.print("  Override: MYCHAPPIE_PROVIDER / MYCHAPPIE_MODEL / MYCHAPPIE_BASE_URL\n\n", .{});
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
        std.debug.print("  - Max Steps:        {d}\n", .{app_cfg.max_steps});
        std.debug.print("  - Dangerous Tools:  {s}\n\n", .{if (app_cfg.dangerously_skip_permissions) "LIBERADAS por configuração" else "BLOQUEADAS por padrão"});
        return;
    }

    if (std.mem.eql(u8, command, "run")) {
        if (args.len < 3) {
            std.debug.print("{s}Erro:{s} Por favor forneça o prompt para execução. Exemplo: mychappie-coder run \"Crie um arquivo teste.txt\"\n", .{ Glamour.Theme.red, Glamour.Theme.reset });
            return;
        }

        try runAgent(allocator, io, init.environ_map, args[2]);
        return;
    }

    if (std.mem.eql(u8, command, "help") or std.mem.eql(u8, command, "--help") or std.mem.eql(u8, command, "-h")) {
        Glamour.printBanner();
        printHelp();
        return;
    }

    try runAgent(allocator, io, init.environ_map, command);
}

fn runAgent(
    allocator: std.mem.Allocator,
    io: std.Io,
    environ_map: *const std.process.Environ.Map,
    prompt: []const u8,
) !void {
    Glamour.printBanner();
    std.debug.print("{s}🎯 OBJETIVO:{s} {s}\n\n", .{ Glamour.Theme.yellow, Glamour.Theme.reset, prompt });

    const app_cfg = mychappie.AppConfig.load(io, ".", environ_map);
    var coder = mychappie.agent.CoderAgent.initWithConfig(allocator, app_cfg) catch |err| {
        std.debug.print(
            "{s}Configuração inválida:{s} não foi possível iniciar o provider '{s}': {s}\n",
            .{ Glamour.Theme.red, Glamour.Theme.reset, @tagName(app_cfg.provider_type), @errorName(err) },
        );
        return err;
    };
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
    std.debug.print("  {s}run <prompt>{s}     Executa o loop autônomo do agente com ferramentas\n", .{ Glamour.Theme.cyan, Glamour.Theme.reset });
    std.debug.print("  {s}tools{s}            Exibe o catálogo de ferramentas disponíveis\n", .{ Glamour.Theme.cyan, Glamour.Theme.reset });
    std.debug.print("  {s}models{s}           Exibe provedores e variáveis de configuração\n", .{ Glamour.Theme.cyan, Glamour.Theme.reset });
    std.debug.print("  {s}info{s}             Exibe diagnóstico do workspace e contexto AllasCode\n", .{ Glamour.Theme.cyan, Glamour.Theme.reset });
    std.debug.print("  {s}version{s}          Exibe informações de versão e compilação Zig v0.16\n", .{ Glamour.Theme.cyan, Glamour.Theme.reset });
    std.debug.print("  {s}help{s}             Exibe esta mensagem de ajuda\n\n", .{ Glamour.Theme.cyan, Glamour.Theme.reset });
    std.debug.print("{s}SEGURANÇA:{s}\n", .{ Glamour.Theme.bold, Glamour.Theme.reset });
    std.debug.print("  Ferramentas perigosas (ex.: bash) ficam bloqueadas por padrão.\n", .{});
    std.debug.print("  Use MYCHAPPIE_DANGEROUSLY_SKIP_PERMISSIONS=true somente quando intencional.\n\n", .{});
}
