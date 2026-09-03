# MyChappie Glamouros Coder — Zig 0.16

MyChappie Glamouros Coder is the Zig 0.16 coding-agent runtime being extracted from the original Crush fork for the AllasCode Agents plane. The active Zig implementation is intentionally explicit about I/O, environment, provider selection, permissions and tool boundaries.

## Current runtime

- Native Zig 0.16 package with `pub fn main(init: std.process.Init) !void`.
- Explicit `init.gpa`, `init.io` and `init.environ_map`; no global process-environment lookup.
- Runtime-selectable LLM provider: Mock, Gemini, OpenAI-compatible, Anthropic and Ollama.
- Autonomous multi-step loop with assistant tool-call history, tool results and provider token accounting.
- Deterministic Mock provider for tests and offline verification.
- ANSI/TrueColor terminal presentation.
- Workspace-local task planning persisted in `.mychappie/todos.ndjson` rather than mutable global memory.

## Tools

| Tool | Purpose | Default permission |
| --- | --- | --- |
| `view` | Read a file with line numbers and optional range | safe |
| `grep` | Recursively search text | safe |
| `glob` | Discover files/directories | safe |
| `todos` | Manage the workspace-local task plan | safe |
| `question` | Request human/policy input; never auto-confirms | safe |
| `write` | Create or replace files | cautious |
| `edit` | Exact validated replacement | cautious |
| `bash` | Execute a shell command | dangerous / denied |

File-oriented calls reject absolute paths and parent traversal (`..`) before dispatch. `bash` is denied by default, limits stdout/stderr to 4 MiB each, supports a relative `cwd`, and has a 120 s default timeout with a 600 s maximum.

`question` does not fabricate a human response. Without an explicitly supplied policy `default_answer`, it returns `Human input required`, allowing an external orchestration layer to suspend/resume the operation.

## Build

Requirement: Zig 0.16.0.

```bash
zig build
```

Artifacts are written to `zig-out/bin/`.

## Validation

Unit tests are deterministic and must not run the autonomous demo as a side effect.

```bash
zig build test
zig build test-regression
zig build test-integration
zig build test-smoke
zig build check
```

`zig build check` aggregates the validation steps configured by `build.zig`.

The GitHub workflow also targets Linux, macOS and Windows with Zig 0.16.0. A workflow result is the authoritative cross-platform validation; a source change should not be described as CI-green until GitHub Actions has actually produced successful check runs.

## CLI

```bash
mychappie-coder version
mychappie-coder tools
mychappie-coder models
mychappie-coder info
mychappie-coder run "Inspect this project and explain the next implementation step"
```

When the first argument is not a known command it is treated as the prompt.

## LLM configuration

Provider discovery can use credentials automatically, but explicit selection is recommended for reproducible execution.

```text
MYCHAPPIE_PROVIDER=mock|gemini|openai|anthropic|ollama
MYCHAPPIE_MODEL=<provider model id>
MYCHAPPIE_BASE_URL=<OpenAI-compatible or Ollama base URL>
MYCHAPPIE_MAX_STEPS=10
MYCHAPPIE_DANGEROUSLY_SKIP_PERMISSIONS=false

GEMINI_API_KEY=...
OPENAI_API_KEY=...
OPENAI_BASE_URL=...
ANTHROPIC_API_KEY=...
OLLAMA_HOST=http://127.0.0.1:11434
```

`MYCHAPPIE_DANGEROUSLY_SKIP_PERMISSIONS=true` is an explicit escape hatch and should only be used when unrestricted shell execution is intentional.

### Provider semantics

- OpenAI-compatible: Chat Completions-style messages and function tools.
- Gemini: `generateContent` with function declarations/calls/responses.
- Anthropic: Messages API with `tool_use` and `tool_result` blocks.
- Ollama: `/api/chat` with native tool calling.
- Mock: deterministic local responses for tests.

Provider/model identifiers are configuration, not architecture. Override `MYCHAPPIE_MODEL` when a provider changes model availability.

## Project structure

```text
build.zig
build.zig.zon
src/
  main.zig
  root.zig
  glamour.zig
  config.zig
  agent/
    agent.zig
    coordinator.zig
    prompts.zig
    session.zig
  llm/
    provider.zig
    client.zig
    http.zig
    mock.zig
    gemini.zig
    openai.zig
    anthropic.zig
    ollama.zig
  permission/
    permission.zig
  tools/
    tool.zig
    registry.zig
    view.zig
    write.zig
    edit.zig
    bash.zig
    grep.zig
    glob.zig
    todos.zig
    question.zig
tests/
legacy_go/
```

`legacy_go/` preserves the previous Go implementation for migration/reference; the Zig runtime does not depend on it.

## Windows terminal encoding

The application emits UTF-8. If legacy Windows PowerShell renders Portuguese characters as mojibake, configure the terminal output encoding before launching the binary, for example:

```powershell
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
```

PowerShell 7 / Windows Terminal normally handle UTF-8 without this workaround.

## License

See `LICENSE.md` for the repository's license terms and upstream attribution.
