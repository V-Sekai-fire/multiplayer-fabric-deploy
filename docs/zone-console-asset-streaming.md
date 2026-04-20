# Zone console asset streaming

Enable `zone_console` to upload a Godot scene to uro, then trigger the
running zone process to stream and instance that scene near the current
player — closing the loop from authoring tool to live world.

## Authoritative design

Asset instancing follows the same authority/interest rules as entity updates:

- **Authority zone** — the zone whose Hilbert range contains
  `hilbert3D(pos)` receives `CMD_INSTANCE_ASSET` and performs the
  actual `ResourceLoader::load()` + `Node::instantiate()`.  No other
  zone may instance the scene at that position.
- **Interest zones** — neighbouring zones within `AOI_CELLS` of the
  authority zone's Hilbert code receive ghost updates of the new node
  via the normal CH_INTEREST broadcast.  They do not re-instance.
- **ReBAC gate** — the authority zone evaluates `rebacCheck` before
  instancing.  `observe` is public (any interest zone may serve the
  node to nearby clients); `modify` requires `owner` relation.

This means `CMD_INSTANCE_ASSET` is routed geometrically, not by a
coordinator.  The console command targets the authority zone for the
given `(x, y, z)` position; that zone fetches the manifest, verifies
chunk hashes, and owns the resulting scene node.

## Platform support

The WebTransport stack (picoquic native) only targets `linux` and `linux-pcvr`
(see `docs/webtransport.md`). **macOS has no native zone-server backend.**

| Component                       | macOS                                                       |
| ------------------------------- | ----------------------------------------------------------- |
| `zone_console`                  | ✅ runs natively (Elixir)                                   |
| `uro` + CockroachDB + VersityGW | ⚠️ Docker only (Linux container) — no native macOS build    |
| Godot zone server               | ⚠️ Docker only (`linux` container) — no native macOS build  |
| WebTransport client             | ✅ `web` (browser), `linux`, `linux-pcvr` — no macOS native |

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
| 6     | Godot zone handler — authority zone instances the scene           | High   | [ ]    | [cycle-6](zone-console-asset-streaming-cycle-6.md) |
| 7     | Round-trip integration smoke test                                 | High   | [ ]    | [cycle-7](zone-console-asset-streaming-cycle-7.md) |
| 8     | Playwright + AccessKit browser smoke test                         | High   | [ ]    | [cycle-8](zone-console-asset-streaming-cycle-8.md) |
