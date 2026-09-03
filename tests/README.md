# Tests

The Zig 0.16 port separates deterministic validation from autonomous side-effect tests.

## Suites

- `zig build test` — unit and component tests declared under `src/`.
- `zig build test-regression` — public API, permission, state-isolation and no-unexpected-side-effect regressions.
- `zig build test-integration` — autonomous `CoderAgent -> MockProvider -> ToolRegistry -> write` flow with filesystem cleanup.
- `zig build test-smoke` — non-interactive CLI commands: `version`, `tools`, `models` and `info`.
- `zig build check` — aggregate validation entry point used by CI.

## Security regressions

Regression tests explicitly verify that dangerous tools such as `bash` are denied by default and cannot create a filesystem probe through the autonomous loop. The CLI only enables this bypass when `run --dangerously-skip-permissions <prompt>` is supplied explicitly.

## Stateful-tool regressions

`todos` has no process-global mutable state. Each `CoderAgent` owns a `ToolRegistry`, and each registry owns its own `TodoStore`. Tests create multiple agents/registries and verify that tasks written to one instance are invisible to the others.

## Rules

Default unit tests must not execute the autonomous loop, ask interactive questions, access external LLMs or leave files behind. Tests that intentionally perform filesystem effects belong in an explicit integration suite and must clean their artifacts.
