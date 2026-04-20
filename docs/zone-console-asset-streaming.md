# Zone console asset streaming

Enable `zone_console` to upload a Godot scene to uro, then trigger the
running zone process to stream and instance that scene near the current
player — closing the loop from authoring tool to live world.

## Cycles (CLI-first order — scaffold drives interface design)

| Cycle | What you get                                                      | Effort | Status |
| ----- | ----------------------------------------------------------------- | ------ | ------ |
| 1     | `upload <path>` command — user can store a scene                  | Low    | [x]    |
| 2     | `UroClient.upload_asset/3` — casync chunk → S3 → uro manifest     | Medium | [x]    |
| 3     | `CMD_INSTANCE_ASSET` wire encoding — protocol ready               | Low    | [x]    |
| 4     | `instance <id> <x> <y> <z>` command — user can trigger instancing | Low    | [x]    |
| 5     | `UroClient.get_manifest/2` — chunk manifest fetch                 | Low    | [x]    |
| 6     | Godot zone handler — zone actually instances the scene            | High   | [ ]    |
| 7     | Round-trip integration smoke test                                 | High   | [ ]    |

## Cycle 1 — `upload <path>` command

Implemented in `multiplayer-fabric-zone-console/lib/zone_console/app.ex`:

```elixir
defp run_command(state, "upload " <> path) do
  path = String.trim(path)
  name = Path.basename(path)

  case UroClient.upload_asset(state.uro, path, name) do
    {:ok, id} ->
      append(state, line(:ok, "Uploaded #{name} as #{id}"))

    {:error, reason} ->
      append(state, line(:err, "Upload failed: #{reason}"))
  end
end
```

## Cycle 2 — UroClient.upload_asset/3

Implemented in `multiplayer-fabric-zone-console/lib/zone_console/uro_client.ex`.
Dependency `{:aria_storage, github: "V-Sekai-fire/aria-storage"}` is declared in
`multiplayer-fabric-zone-console/mix.exs`.

1. `AriaStorage.process_file(path, backend: :s3)` → `{:ok, %{chunks, store_url}}`
2. POST `/storage` with `{name, chunks, store_url}` + Bearer token
3. Return `{:ok, id}`

S3 configured in `multiplayer-fabric-zone-console/config/runtime.exs`:

```elixir
config :aria_storage,
  storage_backend: :s3,
  s3_bucket: System.get_env("AWS_S3_BUCKET", "uro-uploads"),
  s3_endpoint: System.get_env("AWS_S3_ENDPOINT", "http://localhost:7070"),
  aws_access_key_id: System.get_env("AWS_ACCESS_KEY_ID"),
  aws_secret_access_key: System.get_env("AWS_SECRET_ACCESS_KEY")
```

## Cycle 3 — CMD_INSTANCE_ASSET wire protocol

Implemented in `multiplayer-fabric-zone-console/lib/zone_console/zone_client.ex`.
`send_instance/5` public API and `handle_cast({:instance, ...})` encode the
100-byte packet with opcode 4 and split 64-bit asset_id into two u32 payload slots.

## Cycle 4 — `instance <asset_id> <x> <y> <z>` command

Implemented in `multiplayer-fabric-zone-console/lib/zone_console/app.ex`:

```elixir
defp run_command(state, "instance " <> args) do
  case String.split(String.trim(args)) do
    [id_str, x_str, y_str, z_str] ->
      with {id, ""} <- Integer.parse(id_str),
           {x, ""} <- Float.parse(x_str),
           {y, ""} <- Float.parse(y_str),
           {z, ""} <- Float.parse(z_str) do
        if state.zone_client do
          ZoneClient.send_instance(state.zone_client, id, x, y, z)
          append(state, line(:ok, "Instance request sent for asset #{id} at (#{x}, #{y}, #{z})"))
        else
          append(state, line(:warn, "Not joined to a zone. Run 'join' first."))
        end
      else
        _ -> append(state, line(:err, "usage: instance <asset_id> <x> <y> <z>  (int, floats)"))
      end

    _ ->
      append(state, line(:err, "usage: instance <asset_id> <x> <y> <z>"))
  end
end
```

## Cycle 5 — UroClient.get_manifest/2

Implemented in `multiplayer-fabric-zone-console/lib/zone_console/uro_client.ex` —
POST `/storage/:id/manifest`, return `{:ok, %{store_url: _, chunks: [_|_]}}`.

## Cycle 6 — Godot zone: handle CMD_INSTANCE_ASSET

In `multiplayer-fabric-godot` — `FabricMMOGPeer::_process_peer_packet`:

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
