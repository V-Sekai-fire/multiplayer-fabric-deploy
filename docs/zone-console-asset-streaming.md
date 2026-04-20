# Zone console asset streaming

Enable `zone_console` to upload a Godot scene to uro, then trigger the
running zone process to stream and instance that scene near the current
player — closing the loop from authoring tool to live world.

## Cycles (Pareto order — highest value/effort ratio first)

| Cycle | What you get                                                      | Effort | Status |
| ----- | ----------------------------------------------------------------- | ------ | ------ |
| 1     | `UroClient.upload_asset/3` — casync chunk → S3 → uro manifest     | Medium | [ ]    |
| 2     | `upload <path>` command — user can store a scene                  | Low    | [ ]    |
| 3     | `CMD_INSTANCE_ASSET` wire encoding — protocol ready               | Low    | [ ]    |
| 4     | `instance <id> <x> <y> <z>` command — user can trigger instancing | Low    | [ ]    |
| 5     | `UroClient.get_manifest/2` — chunk manifest fetch                 | Low    | [ ]    |
| 6     | Godot zone handler — zone actually instances the scene            | High   | [ ]    |
| 7     | Round-trip integration smoke test                                 | High   | [ ]    |

## Cycle 1 — UroClient.upload_asset/3

Add `{:aria_storage, github: "V-Sekai-fire/aria-storage"}` to
`modules/multiplayer_fabric_mmog/tools/zone_console/mix.exs`.

Implement `UroClient.upload_asset/3`:

1. `AriaStorage.process_file(path, backend: :s3)` → `{:ok, %{chunks, store_url}}`
2. POST `/storage` with `{name, chunks, store_url}` + Bearer token
3. Return `{:ok, id}`

Configure S3 in `config/runtime.exs`:

```elixir
config :aria_storage,
  storage_backend: :s3,
  s3_bucket: System.get_env("AWS_S3_BUCKET", "uro-uploads"),
  s3_endpoint: System.get_env("AWS_S3_ENDPOINT", "http://localhost:7070"),
  aws_access_key_id: System.get_env("AWS_ACCESS_KEY_ID"),
  aws_secret_access_key: System.get_env("AWS_SECRET_ACCESS_KEY")
```

## Cycle 2 — `upload <path>` command

Add `"upload"` clause to `handle_line/2` in `app.ex`; call
`UroClient.upload_asset`, display the returned ID.

## Cycle 3 — CMD_INSTANCE_ASSET wire protocol

Add to `fabric_mmog_peer.h`:

```cpp
CMD_INSTANCE_ASSET = 4,
// payload[1] = shared_file_uuid_hi (u32)
// payload[2] = shared_file_uuid_lo (u32)
// payload[3] = pos_x as bit-cast f32 (u32)
// payload[4] = pos_y as bit-cast f32 (u32)
// payload[5] = pos_z as bit-cast f32 (u32)
```

Add `ZoneClient.send_instance/4` — 100-byte packet, 6 payload slots used.

## Cycle 4 — `instance <asset_id> <x> <y> <z>` command

Add `"instance"` clause to `handle_line/2`; parse asset_id and float
coords; call `ZoneClient.send_instance`.

## Cycle 5 — UroClient.get_manifest/2

Add `get_manifest/2` to `UroClient` — POST `/storage/:id/manifest`,
return `{:ok, %{store_url: _, chunks: [_|_]}}`.

## Cycle 6 — Godot zone: handle CMD_INSTANCE_ASSET

In `FabricMMOGPeer::_process_peer_packet`:

- Add `case CMD_INSTANCE_ASSET:` dispatch
- Extract `asset_id` (two u32 slots → UUID) and `pos` (three f32 slots)
- Call `FabricMMOGAsset::fetch_asset` with the uro manifest URL
- On completion: `ResourceLoader::load()` + `Node::instantiate()` at `pos`

`FabricMMOGAsset::fetch_asset` already handles the caibx index + chunk
download + SHA-512/256 verification pipeline.

## Cycle 7 — Round-trip integration smoke test

Requires CockroachDB + VersityGW + uro + zone all running locally.
Upload a minimal `.tscn`, `instance` it, assert the zone entity list
shows a new entry near `pos`.
