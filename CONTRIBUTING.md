# Contributing

An Elixir release and deployment tool for the multiplayer-fabric
ecosystem.  Builds platform-specific `.tar.gz` binaries (stripping BEAM
bytecode to reduce size), manages release manifests, and drives
multi-target deployments via a `ex_ratatui` TUI.  Uses `egit` for
Git-based release tagging.

Built strictly red-green-refactor: every feature is driven by a failing
test, committed when green, then any cleanup is done with the test
still green.

## Guiding principles

- **RED first, always.** Write a failing test before any implementation.
  Verify the failure message proves the assertion is load-bearing.
- **Error tuples, not exceptions.** All functions return
  `{:ok, value}` / `{:error, reason}`.  Deployment failures must be
  surfaced to the TUI as structured errors, never crash the process.
- **Idempotent releases.** Running the deploy pipeline twice against
  the same tag must produce the same result.  Upload steps check for
  an existing artifact before uploading.  Never overwrite a published
  release binary.
- **Dry-run by default.** Every destructive action (upload, tag push,
  remote exec) must support a `--dry-run` flag that prints what would
  happen without doing it.
- **Commit every green.** One commit per feature cycle.

## Workflow

```
mix deps.get
mix test
mix release                          # local release build
MIX_ENV=prod mix release --overwrite # production strip build
```

## Design notes

### Platform binary stripping

Release archives strip all `.beam` debug info via `mix release` with
`:strip_beams` set to `true`.  Each target platform (linux-amd64,
linux-arm64, darwin-arm64, windows-amd64) produces a separate archive.
Cross-compilation relies on pre-built BEAM runtimes for each target;
do not add a dependency on Docker unless it is already required by the
deployment target.

### Git tagging via egit

Release versions are driven by Git tags.  `egit` reads the current tag
and validates it follows semver before building.  Never hardcode version
strings in source files; always derive from `mix.exs` which derives
from the Git tag.
