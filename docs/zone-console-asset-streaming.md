# Zone console asset streaming

Upload a raw asset (GLB) or pre-baked scene to uro from `zone_console`, trigger the [ephemeral bake](ephemeral-asset-bake-microservice.md) if necessary, then instance it in the live world via `CMD_INSTANCE_ASSET`.

## Authoritative design

1. **Authority** — the zone whose Hilbert range contains `hilbert3D(pos)` receives and executes `CMD_INSTANCE_ASSET`. No other zone instances the scene.
2. **Interest** — neighbouring zones within `AOI_CELLS` receive a CH_INTEREST ghost of the new node. They do not re-fetch or re-instance.
3. **ReBAC** — the authority zone evaluates `rebacCheck` before instancing. `observe` is public; `modify` requires `owner`.
4. **Headless Baking** — production zone servers do not contain editor code. All `.tscn` / `.godot/imported` generation occurs in the [ephemeral-asset-bake-microservice](ephemeral-asset-bake-microservice.md).
5. **Infrastructure** — All operational components (Bakers and Zone Servers) run on **Fly.io** using Elixir FLAME for elastic orchestration.

## Platform support

The WebTransport stack targets `linux` and `linux-pcvr`. **Web/Browser support is not supported.**

| Component                       | Hosting / Platform                                                           |
| ------------------------------- | ---------------------------------------------------------------------------- |
| `zone_console`                  | ✅ runs natively (Elixir)                                                    |
| `uro` + CockroachDB + VersityGW | ⚠️ Docker only (Linux) — no native macOS build                               |
| Godot zone server               | ✅ Fly.io FLAME (headless Linux)                                             |
| WebTransport client             | ✅ `linux`, `linux-pcvr`                                                     |
| Godot `template_debug/release`  | ⚠️ Linux only — produced in CI and consumed by FLAME                         |

Local template builds use `gtscons` / `gtrscons` which wrap Docker:

```sh
# run from multiplayer-fabric-godot root
gtscons   # target=template_debug  via Linux container
gtrscons  # target=template_release via Linux container
```

`target=template_debug` and `target=template_release` for `linuxbsd` are built
in CI (`linux_builds.yml`) and consumed by the zone-fabric Docker container.
Local template builds use `gtscons` / `gtrscons` which wrap Docker:

```sh
# run from multiplayer-fabric-godot root
gtscons   # target=template_debug  via Linux container
gtrscons  # target=template_release via Linux container
```

Run the full stack on macOS with:

```sh
cd multiplayer-fabric-hosting
docker compose up -d   # starts crdb, versitygw, uro, zone-server (Linux container)
```

The zone-server container listens on UDP 443 and is reachable at `localhost` or
`zone-700a.chibifire.com` depending on your `.env`.

## Cycles

| Cycle | What you get                                                      | Effort | Status | Detail |
| ----- | ----------------------------------------------------------------- | ------ | ------ | ------ |
| 1     | `upload <path>` command — user can store a scene                  | Low    | [x]    | [cycle-1](zone-console-asset-streaming-cycle-1.md) |
| 2     | `UroClient.upload_asset/3` — casync chunk → S3 → uro manifest     | Medium | [x]    | [cycle-2](zone-console-asset-streaming-cycle-2.md) |
| 3     | `CMD_INSTANCE_ASSET` wire encoding — protocol ready               | Low    | [x]    | [cycle-3](zone-console-asset-streaming-cycle-3.md) |
| 4     | `instance <id> <x> <y> <z>` command — user can trigger instancing | Low    | [x]    | [cycle-4](zone-console-asset-streaming-cycle-4.md) |
| 5     | `UroClient.get_manifest/2` — chunk manifest fetch                 | Low    | [x]    | [cycle-5](zone-console-asset-streaming-cycle-5.md) |
| 6     | FLAME Asset Baker — Ephemeral SCons `editor=yes` import pipeline  | Medium | [/]    | [flame-bake](ephemeral-asset-bake-microservice.md) |
| 7     | FLAME Zone Orchestrator — Elastic `editor=no` server placement    | High   | [ ]    | [control-plane](zone-console-operational-control-plane.md) |
| 8     | Godot zone handler — authority zone instances the baked scene     | High   | [ ]    | [cycle-6](zone-console-asset-streaming-cycle-6.md) |
| 9     | Round-trip integration smoke test                                 | High   | [ ]    | [cycle-7](zone-console-asset-streaming-cycle-7.md) |
| 10    | Playwright + AccessKit browser smoke test                         | High   | [ ]    | [cycle-8](zone-console-asset-streaming-cycle-8.md) |
