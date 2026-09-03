# MyChappie Glamouros Coder — Development Guide (Zig v0.16)

## Project Overview

**MyChappie Glamouros Coder** é um assistente de código autônomo de alta performance desenvolvido nativamente em **Zig v0.16**.
Ele integra a arquitetura **Multi-Plane** do **AllasCode** no plano **Planes/Agents**, adotando a metodologia **SOTA-DD** (State-of-the-Art-Driven Development).

O projeto conta com:
- Interface glamourosa em terminal ANSI (Truecolor 24-bit, caixas estilizadas, realce de sintaxe e diffs).
- Loop autônomo multi-turn de raciocínio, planejamento e execução de ferramentas.
- Conjunto completo de ferramentas nativas de desenvolvimento (`bash`, `view`, `write`, `edit`, `grep`, `glob`, `todos`, `question`).
- Camada de LLM multi-provedor (Google Gemini, OpenAI, Anthropic Claude, Ollama Local e Mock determinístico).
- Motor de permissões e segurança.

## Arquitetura (Zig v0.16)

```
build.zig.zon                          Manifesto do pacote Zig 0.16
build.zig                              Pipeline de compilação (executable + library + tests)
src/
  main.zig                             Ponto de entrada CLI (subcomandos: run, tools, models, info, version)
  root.zig                             Módulo público da biblioteca 'mychappie_coder'
  glamour.zig                          Sistema de TUI e estilização ANSI Truecolor
  config.zig                           Carregamento de configurações de ambiente e contexto
  agent/
    agent.zig                          Loop autônomo CoderAgent (intake → LLM → tool dispatch → feedback)
    coordinator.zig                    Coordenador de agentes especialistas (Coder, Architect, Reviewer)
    prompts.zig                        System prompts nativos especializados
    session.zig                        Gerenciamento de estado, histórico e sessões
  tools/
    tool.zig                           Contrato e interface universal de ferramentas (Tool / ToolResult)
    view.zig                           Leitura de arquivos com numeração de linhas e limites
    write.zig                          Criação e sobrescrita atômica com diretórios pais automáticos
    edit.zig                           Substituição cirúrgica exata com diff sintético
    bash.zig                           Execução de subprocessos de terminal multiplataforma
    grep.zig                           Busca recursiva em árvore de diretórios por padrões
    glob.zig                           Descoberta de arquivos por máscaras e extensões
    todos.zig                          Gestão de tarefas e planejamento do agente
    question.zig                       Perguntas interativas e confirmações do usuário
    registry.zig                       Registro e despacho centralizado de ferramentas
  llm/
    provider.zig                       Contratos unificados de mensagens, chamadas de ferramentas e provedores
    mock.zig                           Provedor determinístico offline para testes e CI
    gemini.zig                         Cliente Google Gemini REST API
    openai.zig                         Cliente OpenAI / OpenRouter / DeepSeek REST API
    anthropic.zig                      Cliente Anthropic Claude Messages API
    ollama.zig                         Cliente Ollama local offline
  permission/
    permission.zig                     Classificador e guardião de permissões de ferramentas
legacy_go/                             Código Go anterior mantido como referência histórica
```

## Comandos de Build & Testes

Compilar o binário nativo:
```bash
zig build
```
O executável será gerado em: `zig-out/bin/mychappie-coder.exe` (ou `mychappie-coder` no Linux/macOS).

Executar a suíte de testes unitários:
```bash
zig build test
```

Executar via `zig build run`:
```bash
zig build run -- version
zig build run -- tools
zig build run -- models
zig build run -- info
zig build run -- run "Crie um arquivo teste.txt com conteúdo Olá Chappie"
```

## Diretrizes de Código & Convenções

- **Zig 0.16 I/O**: Utilize `std.Io` e `std.process.Init` para operações assíncronas e I/O estruturado.
- **Gerenciamento de Memória**: Alocações explícitas via `allocator`, com liberação obrigatória via `defer` ou `deinit()`.
- **Formatação ANSI**: Use os tokens do módulo `glamour.zig` para padronizar cores e bordas no terminal.
