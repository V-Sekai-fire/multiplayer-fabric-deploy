# AGENTS.md — multiplayer-fabric-deploy

Guidance for AI coding agents working in this submodule.

## What this is

Terminal UI (TUI) deployment tool for the multiplayer-fabric stack. Lists
available deployment tasks (build, push, migrate, etc.), runs them on
selection, and streams output to a log pane. Packaged as a self-contained
binary via Burrito (Linux x86_64 target).

## Build and test

```sh
mix compile
mix test

# Build self-contained binary (requires Burrito + Linux ERTS)
mix release
```

For CI, set `BURRITO_CUSTOM_ERTS` to a local 3-segment OTP tarball path
when the installed OTP has a 4-segment version string the Burrito CDN does
not carry.

## Key files

| Path | Purpose |
|------|---------|
| `mix.exs` | Deps: ex_ratatui, egit, taskweft (local path), burrito |
| `lib/multiplayer_fabric_deploy.ex` | TUI event loop (ex_ratatui) |
| `lib/multiplayer_fabric_deploy/tasks.ex` | Registry of deploy tasks |
| `lib/multiplayer_fabric_deploy/runner.ex` | Async task execution, stdout streaming |

## Conventions

- `taskweft` is declared as a local path dep (`path: "../multiplayer-fabric-taskweft"`).
  Keep the relative path correct if the repo layout changes.
- Logs are written to `Config.logs_dir()` with timestamped filenames.
- Every new `.ex` / `.exs` file needs SPDX headers:
  ```elixir
  # SPDX-License-Identifier: MIT
  # Copyright (c) 2026 K. S. Ernest (iFire) Lee
  ```
- Commit message style: sentence case, no `type(scope):` prefix.
  Example: `Add migrate task to deploy task registry`
