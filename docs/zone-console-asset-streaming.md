# Zone console asset streaming

Enable `zone_console` to upload a Godot scene to uro, then trigger the
running zone process to stream and instance that scene near the current
player — closing the loop from authoring tool to live world.

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
| 8     | Playwright + AccessKit browser smoke test — upload scene to desync S3, send `CMD_INSTANCE_ASSET` via WebTransport, verify instanced node appears in AccessKit tree next to player | High   | [ ]    |

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

> **macOS note:** the Godot zone process runs inside the `zone-server` Docker
> container (Linux). Build and test changes via `docker compose build zone-server
&& docker compose up -d zone-server`. There is no native macOS zone-server binary.

In `multiplayer-fabric-godot` — `FabricMMOGPeer::_process_peer_packet`:

- Add `case CMD_INSTANCE_ASSET:` dispatch
- Extract `asset_id` (two u32 slots → UUID) and `pos` (three f32 slots)
- Call `FabricMMOGAsset::fetch_asset` with the uro manifest URL
- On completion: `ResourceLoader::load()` + `Node::instantiate()` at `pos`

`FabricMMOGAsset::fetch_asset` already handles the caibx index + chunk
download + SHA-512/256 verification pipeline.

## Cycle 7 — Round-trip integration smoke test

Requires CockroachDB + VersityGW + uro + zone all running locally.
On macOS, "locally" means via Docker — start the stack first:

```sh
cd multiplayer-fabric-hosting && docker compose up -d
```

Then from `zone_console` (runs natively on macOS):

```
join zone-700a.chibifire.com   # or localhost if DNS not set
upload path/to/minimal.tscn
instance <returned-id> 0.0 1.0 0.0
```

Assert the zone entity list shows a new entry near `pos`.

## Cycle 8 — Playwright + AccessKit browser smoke test

> **Depends on:** Cycles 6 and 7 complete.

### Preconditions

- Full Docker stack running: `cd multiplayer-fabric-hosting && docker compose up -d`
- Godot web export built with `gescons` (`accesskit=yes` already set) and served:
  ```sh
  npx serve bin/ --listen 8060
  ```
- `zone_console` running natively on macOS and joined to the zone

### Test fixture

`tests/fixtures/minimal.tscn` — single `MeshInstance3D` root node, no scripts.
The root node name (`minimal`) is what AccessKit surfaces in the accessibility tree.

### Test script (`tests/e2e/test_asset_streaming.spec.ts`)

```typescript
import { test, expect } from '@playwright/test';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';

const exec = promisify(execFile);

async function consoleCmd(cmd: string): Promise<string> {
  const { stdout } = await exec('zone_console', ['--cmd', cmd]);
  return stdout;
}

test('instance scene near player via WebTransport', async ({ page }) => {
  // 1. Load Godot web client and wait for AccessKit root
  await page.goto('http://localhost:8060');
  await page.getByRole('application', { name: 'Godot Engine' }).waitFor();

  // 2. Join zone
  await consoleCmd('join zone-700a.chibifire.com');

  // 3. Upload scene to desync S3 via uro
  const uploadOut = await consoleCmd('upload tests/fixtures/minimal.tscn');
  const assetId = uploadOut.match(/as (\d+)/)?.[1];
  if (!assetId) throw new Error(`Upload failed: ${uploadOut}`);

  // 4. Send CMD_INSTANCE_ASSET via WebTransport
  await consoleCmd(`instance ${assetId} 0.0 1.0 0.0`);

  // 5. Verify AccessKit tree reflects the instanced node next to player
  //    The instanced scene root is exposed as a named group by AccessKit.
  const node = page.getByRole('group', { name: 'minimal' });
  await expect(node).toBeVisible({ timeout: 15_000 });
});
```

### AccessKit note

`gescons` already passes `accesskit=yes` to SCons. The instanced scene's root
node name is used as the accessible name — use a descriptive root node name in
production scenes so the accessibility tree remains meaningful.

### Pass condition

`getByRole('group', { name: 'minimal' })` becomes visible within 15 s of the
`instance` command. This confirms the full pipeline: S3 upload → uro manifest →
`CMD_INSTANCE_ASSET` wire packet → zone handler → WebTransport push → web client
scene instantiation → AccessKit tree update.
