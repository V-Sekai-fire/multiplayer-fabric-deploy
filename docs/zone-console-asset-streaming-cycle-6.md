# Cycle 6 — FLAME asset baker

**Status:** [ ] RED  
**Effort:** Medium  
**Back:** [index](zone-console-asset-streaming.md)  
**Depends on:** Cycle 2

## What you get

When a raw GLB or .tscn is uploaded, uro spawns an ephemeral Fly.io machine
(`editor=yes` build) that runs `godot --headless --import`, tarballs
`.godot/imported`, uploads the result to Tigris, and updates the manifest.
Zone servers only fetch the pre-baked artefact — they carry no editor code.

## Architecture

```
UroClient.upload_asset/3
  → POST /storage (raw chunks in Tigris)
  → uro backend triggers FLAME.call(Uro.AssetBaker, fn -> ...)
      → ephemeral Fly machine image: registry.fly.io/multiplayer-fabric-uro:editor-latest
      → godot --headless --path . --import
      → tar .godot/imported → upload baked tarball to Tigris
      → return %{baked_url: ..., chunks: [...]}
  → uro updates manifest: adds baked_url field
```

Zone servers query `GET /storage/:id/manifest` and receive both raw chunks and
the `baked_url`. They use the baked version for `sandbox_load`.

## RED — failing test

File: `test/zone_console/uro_client_bake_test.exs`

```elixir
defmodule ZoneConsole.UroClientBakeTest do
  use ExUnit.Case, async: false

  @tag :prod
  test "uploaded asset manifest includes baked_url after baker completes" do
    client =
      ZoneConsole.UroClient.new(System.fetch_env!("URO_BASE_URL"))
      |> then(fn c ->
        {:ok, authed} = ZoneConsole.UroClient.login(c,
          System.fetch_env!("URO_EMAIL"),
          System.fetch_env!("URO_PASSWORD"))
        authed
      end)

    scene_path = System.fetch_env!("TEST_SCENE_PATH")
    {:ok, id} = ZoneConsole.UroClient.upload_asset(client, scene_path,
      Path.basename(scene_path))

    # Baker is async — poll up to 30 s for baked_url to appear
    baked_url =
      Enum.find_value(1..30, fn _ ->
        {:ok, m} = ZoneConsole.UroClient.get_manifest(client, id)
        url = m["baked_url"] || m[:baked_url]
        if url, do: url, else: (Process.sleep(1_000); nil)
      end)

    assert is_binary(baked_url), "manifest must have baked_url within 30 s"
    assert String.starts_with?(baked_url, "https://")
  end
end
```

Run with:

```sh
cd multiplayer-fabric-zone-console
URO_BASE_URL=https://uro.chibifire.com \
URO_EMAIL=... URO_PASSWORD=... \
TEST_SCENE_PATH=../multiplayer-fabric-humanoid-project/humanoid/scenes/mire.tscn \
AWS_S3_BUCKET=uro-uploads AWS_S3_ENDPOINT=https://fly.storage.tigris.dev \
AWS_ACCESS_KEY_ID=... AWS_SECRET_ACCESS_KEY=... \
mix test --only prod test/zone_console/uro_client_bake_test.exs
```

## GREEN — pass condition

The test passes within 30 s. The manifest `baked_url` points to a Tigris object.
Confirm the ephemeral baker machine appeared and was destroyed:

```sh
fly machines list --app multiplayer-fabric-uro | grep baker
```

## REFACTOR

Extract the poll-until helper into `ZoneConsole.TestHelpers.poll_until/3` for
reuse in Cycle 9's round-trip test.

## Fly.io deployment steps

### 1. Build the editor image

```sh
cd multiplayer-fabric-godot
# SCons editor=yes linuxbsd headless build
docker build --target editor-latest \
  -t registry.fly.io/multiplayer-fabric-uro:editor-latest \
  -f Dockerfile.baker .
fly auth docker
docker push registry.fly.io/multiplayer-fabric-uro:editor-latest
```

### 2. Add the FLAME pool to uro's application.ex

```elixir
# lib/uro/application.ex — add to children list:
{FLAME.Pool,
  name: Uro.AssetBaker,
  backend: {FLAME.FlyBackend,
    image: "registry.fly.io/multiplayer-fabric-uro:editor-latest",
    env: %{"GODOT_MODE" => "baker"}
  },
  min: 0, max: 10,
  cpu_kind: "performance-2x", memory_mb: 4096,
  idle_shutdown_after: 30_000}
```

### 3. Deploy uro

```sh
fly deploy --app multiplayer-fabric-uro
```

### 4. Add baked_url to manifest endpoint

In `multiplayer-fabric-zone-backend`, update `POST /storage/:id/manifest` to
include `baked_url` once the baker has finished. Store bake status in a
CockroachDB column `baked_at` on the `shared_files` table.

## Cloudflare check

The manifest endpoint `POST /storage/:id/manifest` must not be cached.
Confirm:

```sh
curl -sI -X POST https://uro.chibifire.com/storage/<id>/manifest \
  -H "Authorization: Bearer $TOKEN" | grep cf-cache-status
# expect DYNAMIC or MISS
```
