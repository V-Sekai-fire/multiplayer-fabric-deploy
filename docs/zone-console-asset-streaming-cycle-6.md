# Cycle 6 — Asset baker (Docker `editor=yes`)

**Status:** [ ] RED  
**Effort:** Medium  
**Back:** [index](zone-console-asset-streaming.md)  
**Depends on:** Cycle 2

## What you get

When a raw GLB or .tscn is uploaded, uro triggers a Docker container running
the Godot editor binary in headless mode (`editor=yes` build). The baker runs
`godot --headless --import`, tarballs `.godot/imported`, uploads the result to
VersityGW, and updates the manifest with a `baked_url` field. Zone servers
only fetch the pre-baked artefact — they carry no editor code.

## Infrastructure

```
zone-backend (Docker)
  → spawn baker container (one-shot, editor=yes image)
  → baker: godot --headless --path /scene --import
  → baker: tar .godot/imported → upload to versitygw:7070/uro-uploads/
  → baker: POST /storage/:id/bake {baked_url}
  → zone-backend: update manifest record in CockroachDB
  → baker container exits
```

The baker is a separate Docker image built from the same Godot source with
`editor=yes` SCons flag. It runs as a one-shot container on the host, not a
long-lived service.

## RED — failing test

File: `test/zone_console/uro_client_bake_test.exs`

```elixir
defmodule ZoneConsole.UroClientBakeTest do
  use ExUnit.Case, async: false

  defp authed_client do
    ZoneConsole.UroClient.new(System.fetch_env!("URO_BASE_URL"))
    |> then(fn c ->
      {:ok, a} = ZoneConsole.UroClient.login(c,
        System.fetch_env!("URO_EMAIL"),
        System.fetch_env!("URO_PASSWORD"))
      a
    end)
  end

  @tag :prod
  test "uploaded asset manifest includes baked_url after baker completes" do
    client     = authed_client()
    scene_path = System.fetch_env!("TEST_SCENE_PATH")
    {:ok, id}  = ZoneConsole.UroClient.upload_asset(client, scene_path,
      Path.basename(scene_path))

    # Baker is async — poll up to 30 s for baked_url to appear
    baked_url =
      Enum.find_value(1..30, fn _ ->
        {:ok, m} = ZoneConsole.UroClient.get_manifest(client, id)
        url = m["baked_url"] || m[:baked_url]
        if url, do: url, else: (Process.sleep(1_000); nil)
      end)

    assert is_binary(baked_url), "manifest must have baked_url within 30 s"
    assert String.contains?(baked_url, "versitygw") or
           String.contains?(baked_url, "localhost") or
           String.contains?(baked_url, "7070"),
           "baked_url must point to local VersityGW store"
  end
end
```

Run with the same env vars as Cycle 2.

## GREEN — pass condition

Test passes within 30 s. The `baked_url` points to an object in the
`uro-uploads` bucket on VersityGW. Confirm:

```sh
# Baker container was created and exited cleanly
docker ps -a --filter ancestor=multiplayer-fabric-godot-baker:latest | head -5

# Baked tarball exists in VersityGW
AWS_ACCESS_KEY_ID=minioadmin AWS_SECRET_ACCESS_KEY=minioadmin \
  aws --endpoint-url http://localhost:7070 \
  s3 ls s3://uro-uploads/ | grep ".tar.gz"

# Manifest now has baked_url
curl -s -X POST https://hub-700a.chibifire.com/storage/<id>/manifest \
  -H "Authorization: Bearer $TOKEN" | python3 -m json.tool | grep baked_url
```

## Implementation steps

### 1. Build the baker image

```sh
cd multiplayer-fabric-godot
docker build --target baker \
  -t multiplayer-fabric-godot-baker:latest \
  -f Dockerfile.baker .
```

The `baker` target compiles Godot with `editor=yes scons_cache_limit=4096`.

### 2. Add baker trigger to zone-backend

In `multiplayer-fabric-zone-backend/lib/uro/shared_content.ex`, after
`create_shared_file/1` succeeds, spawn a Task:

```elixir
Task.start(fn ->
  System.cmd("docker", [
    "run", "--rm",
    "--network", "multiplayer-fabric-hosting_default",
    "-v", "#{tmp_dir}:/scene",
    "-e", "ASSET_ID=#{id}",
    "-e", "URO_URL=http://zone-backend:4000",
    "-e", "VERSITYGW_URL=http://versitygw:7070",
    "multiplayer-fabric-godot-baker:latest"
  ])
end)
```

### 3. Add bake endpoint

`POST /storage/:id/bake` accepts `{baked_url: ...}` and sets
`baked_url` on the `shared_files` record. Add the column via migration.

## REFACTOR

Once green, move the `Task.start` into a supervised `Uro.Baker` GenServer
so crashes are observable and restarts are bounded.
