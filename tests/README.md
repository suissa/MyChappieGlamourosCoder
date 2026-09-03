# Tests

The Zig 0.16 port separates deterministic validation from autonomous side-effect tests.

## Suites

- `zig build test` — unit and component tests declared under `src/`.
- `zig build test-regression` — public API, permission and no-unexpected-side-effect regressions.
- `zig build test-integration` — autonomous `CoderAgent -> MockProvider -> ToolRegistry -> write` flow with filesystem cleanup.
- `zig build test-smoke` — non-interactive CLI commands: `version`, `tools`, `models` and `info`.
- `zig build check` — aggregate validation entry point used by CI.

## Rules

Default unit tests must not execute the autonomous loop, ask interactive questions, access external LLMs or leave files behind. Tests that intentionally perform filesystem effects belong in an explicit integration suite and must clean their artifacts.
