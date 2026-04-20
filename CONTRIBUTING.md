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
- **Commit every green.** One commit per feature cycle.  Messages use
  sentence case; do not use Conventional Commits prefixes (`feat:`,
  `fix:`, `chore:`, etc.).

## Deploy to production (Fly.io)

All configs live in `multiplayer-fabric-fly/`. Images are built externally and pushed to GHCR before deploying.

### Cycles (dependency order)

| Cycle | What you get | Effort | Status |
| ----- | ------------ | ------ | ------ |
| 1 | Build + push `multiplayer-fabric-zone-backend` Docker image via `multiplayer-fabric-zone-backend` CI | Medium | [ ] |
| 2 | Build + push `multiplayer-fabric-godot-server` Docker image via `multiplayer-fabric-deploy` CI | High | [ ] |
| 3 | Build + push `ghcr.io/v-sekai/cockroach` Docker image via `v-sekai/cockroach` CI | Medium | [ ] |
| 4 | Create Fly apps and provision Tigris bucket | Low | [ ] |
| 5 | Deploy CockroachDB (`multiplayer-fabric-crdb`) with persistent volume | Low | [ ] |
| 6 | Deploy zone-backend (`multiplayer-fabric-uro`) and wire secrets | Low | [ ] |
| 7 | Deploy zone servers (`multiplayer-fabric-zones`) and smoke test | Low | [ ] |

### Cycle 1 — zone-backend Docker image

Add a `Dockerfile` to `multiplayer-fabric-zone-backend` and a GitHub Actions workflow that builds and pushes `ghcr.io/v-sekai-fire/multiplayer-fabric-zone-backend:latest` on every push to `main`.

### Cycle 2 — Godot server Docker image

Add a `Dockerfile` to `multiplayer-fabric-deploy` that cross-compiles the headless Godot server binary (aarch64) and packages it. Push `ghcr.io/v-sekai-fire/multiplayer-fabric-godot-server:latest` on every release tag.

### Cycle 3 — CockroachDB fork image

Add a GitHub Actions workflow to `v-sekai/cockroach` that builds from the `release-22.1-oxide` branch and pushes `ghcr.io/v-sekai/cockroach:latest`.

### Cycle 4 — Fly app provisioning

```bash
fly apps create multiplayer-fabric-uro
fly apps create multiplayer-fabric-zones
fly apps create multiplayer-fabric-crdb
fly storage create                          # creates Tigris bucket, outputs credentials
```

### Cycle 5 — CockroachDB

```bash
fly volumes create crdb_data --app multiplayer-fabric-crdb --region yyz --size 80
fly deploy --config multiplayer-fabric-fly/crdb/fly.toml
```

### Cycle 6 — Zone backend

```bash
fly secrets set --app multiplayer-fabric-uro \
  DATABASE_URL="postgresql://root@<crdb-private-host>:26257/production" \
  AWS_S3_BUCKET="<tigris-bucket>" \
  AWS_S3_ENDPOINT="https://fly.storage.tigris.dev" \
  AWS_ACCESS_KEY_ID="<key>" \
  AWS_SECRET_ACCESS_KEY="<secret>"
fly deploy --config multiplayer-fabric-fly/uro/fly.toml
```

### Cycle 7 — Zone servers

```bash
fly deploy --config multiplayer-fabric-fly/zones/fly.toml
# Smoke test: join a zone from the console, upload a minimal scene, instance it
```

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
