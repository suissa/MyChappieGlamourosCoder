const std = @import("std");
const mychappie = @import("mychappie_coder");
const Glamour = mychappie.Glamour;

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const io = init.io;

    // Parse command line arguments via init.minimal.args
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
        std.debug.print("  {s}Runtime:{s}   std.Io.Threaded High-Performance Event Loop\n\n", .{ Glamour.Theme.slate, Glamour.Theme.reset });
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
        std.debug.print("  • {s}Google Gemini{s}       (gemini-2.5-pro, gemini-2.5-flash via GEMINI_API_KEY)\n", .{ Glamour.Theme.cyan, Glamour.Theme.reset });
        std.debug.print("  • {s}OpenAI / Compatible{s}   (gpt-4o, openrouter, deepseek via OPENAI_API_KEY)\n", .{ Glamour.Theme.green, Glamour.Theme.reset });
        std.debug.print("  • {s}Anthropic Claude{s}     (claude-3-5-sonnet via ANTHROPIC_API_KEY)\n", .{ Glamour.Theme.orange, Glamour.Theme.reset });
        std.debug.print("  • {s}Ollama Local{s}         (offline inference via OLLAMA_HOST, default: localhost:11434)\n", .{ Glamour.Theme.slate, Glamour.Theme.reset });
        std.debug.print("  • {s}Deterministic Mock{s}   (offline verification and testing)\n\n", .{ Glamour.Theme.yellow, Glamour.Theme.reset });
        return;
    }

    if (std.mem.eql(u8, command, "info")) {
        Glamour.printBanner();
        const app_cfg = mychappie.AppConfig.load(io, ".", init.environ_map);
        std.debug.print("{s}📊 DIAGNÓSTICO DO AMBIENTE:{s}\n", .{ Glamour.Theme.cyan, Glamour.Theme.reset });
        std.debug.print("  - Workspace:        {s}\n", .{app_cfg.workspace_root});
        std.debug.print("  - AGENTS.md:        {s}\n", .{if (app_cfg.has_agents_md) "Encontrado ✔" else "Não encontrado (usando padrão)"});
        std.debug.print("  - Active Provider:  {s}\n", .{@tagName(app_cfg.provider_type)});
        std.debug.print("  - Active Model:     {s}\n\n", .{app_cfg.model});
        return;
    }

    if (std.mem.eql(u8, command, "run")) {
        if (args.len < 3) {
            std.debug.print("{s}Erro:{s} Por favor forneça o prompt para execução. Exemplo: mychappie-coder run \"Crie um arquivo teste.txt\"\n", .{ Glamour.Theme.red, Glamour.Theme.reset });
            return;
        }

        const prompt = args[2];
        Glamour.printBanner();

        std.debug.print("{s}🎯 OBJETIVO:{s} {s}\n\n", .{ Glamour.Theme.yellow, Glamour.Theme.reset, prompt });

        var coder = try mychappie.agent.CoderAgent.init(allocator, ".", .{
            .max_steps = 10,
            .model = "mock-chappie-v1",
            .dangerously_skip_permissions = true,
        });
        defer coder.deinit(allocator);

        const result = try coder.executeTurn(allocator, io, prompt);
        defer allocator.free(result);

        std.debug.print("\n", .{});
        try Glamour.printBox(allocator, "RESPOSTA DO AGENTE", result, Glamour.Theme.green);
        std.debug.print("\n", .{});
        return;
    }

    if (std.mem.eql(u8, command, "help") or std.mem.eql(u8, command, "--help") or std.mem.eql(u8, command, "-h")) {
        Glamour.printBanner();
        printHelp();
        return;
    }

    // Default: treat arguments as prompt to run
    Glamour.printBanner();
    const prompt = args[1];
    std.debug.print("{s}🎯 OBJETIVO:{s} {s}\n\n", .{ Glamour.Theme.yellow, Glamour.Theme.reset, prompt });

    var coder = try mychappie.agent.CoderAgent.init(allocator, ".", .{
        .max_steps = 10,
        .model = "mock-chappie-v1",
        .dangerously_skip_permissions = true,
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
    std.debug.print("  {s}run <prompt>{s}     Executa o loop autônomo do agente com ferramentas\n", .{ Glamour.Theme.cyan, Glamour.Theme.reset });
    std.debug.print("  {s}tools{s}            Exibe o catálogo de ferramentas disponíveis\n", .{ Glamour.Theme.cyan, Glamour.Theme.reset });
    std.debug.print("  {s}models{s}           Exibe a lista de modelos e provedores suportados\n", .{ Glamour.Theme.cyan, Glamour.Theme.reset });
    std.debug.print("  {s}info{s}             Exibe diagnóstico do workspace e contexto AllasCode\n", .{ Glamour.Theme.cyan, Glamour.Theme.reset });
    std.debug.print("  {s}version{s}          Exibe informações de versão e compilação Zig v0.16\n", .{ Glamour.Theme.cyan, Glamour.Theme.reset });
    std.debug.print("  {s}help{s}             Exibe esta mensagem de ajuda\n\n", .{ Glamour.Theme.cyan, Glamour.Theme.reset });
}
