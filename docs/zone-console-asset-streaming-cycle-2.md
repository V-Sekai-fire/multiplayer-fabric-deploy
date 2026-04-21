# Cycle 2 — `UroClient.upload_asset/3`

**Status:** [ ] RED  
**Effort:** Medium  
**Back:** [index](zone-console-asset-streaming.md)  
**Depends on:** Cycle 1

## What you get

`UroClient.upload_asset/3` chunks a local scene file via AriaStorage, uploads
chunks to VersityGW (local S3), and registers a manifest entry in uro.
Returns `{:ok, id}` where `id` is the asset UUID.

## Infrastructure path

```
zone_console (macOS)
  → AriaStorage.process_file/2
  → chunks written to VersityGW (http://localhost:7070, bucket uro-uploads)
  → HTTPS POST /storage
  → Cloudflare Tunnel → zone-backend:4000
  → manifest stored in CockroachDB
  → {:ok, id}
```

VersityGW is the S3-compatible object store running in Docker on port 7070.
`zone_console` writes chunks directly to `localhost:7070` (plain HTTP, no
Cloudflare in this path). Only the manifest registration goes through the
Cloudflare Tunnel.

## RED — failing test

File: `test/zone_console/uro_client_upload_test.exs`

```elixir
defmodule ZoneConsole.UroClientUploadTest do
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
  test "upload_asset stores file and returns non-empty id" do
    client     = authed_client()
    scene_path = System.fetch_env!("TEST_SCENE_PATH")

    {:ok, id} = ZoneConsole.UroClient.upload_asset(client, scene_path,
      Path.basename(scene_path))

    assert is_binary(id)
    assert byte_size(id) > 0
  end

  @tag :prod
  test "uploaded asset is queryable via GET /storage/:id" do
    client     = authed_client()
    scene_path = System.fetch_env!("TEST_SCENE_PATH")
    {:ok, id}  = ZoneConsole.UroClient.upload_asset(client, scene_path,
      Path.basename(scene_path))

    {:ok, %{status: 200}} =
      Req.get("#{System.fetch_env!("URO_BASE_URL")}/storage/#{id}",
        headers: [{"authorization", "Bearer #{client.access_token}"}])
  end
end
```

Run:

```sh
cd multiplayer-fabric-zone-console
URO_BASE_URL=https://hub-700a.chibifire.com \
URO_EMAIL=... URO_PASSWORD=... \
TEST_SCENE_PATH=../multiplayer-fabric-humanoid-project/humanoid/scenes/mire.tscn \
AWS_S3_BUCKET=uro-uploads \
AWS_S3_ENDPOINT=http://localhost:7070 \
AWS_ACCESS_KEY_ID=minioadmin \
AWS_SECRET_ACCESS_KEY=minioadmin \
mix test --only prod test/zone_console/uro_client_upload_test.exs
```

## GREEN — pass condition

Both tests pass. Confirm the chunk landed in VersityGW:

```sh
# List objects in the bucket via S3 API
AWS_ACCESS_KEY_ID=minioadmin \
AWS_SECRET_ACCESS_KEY=minioadmin \
aws --endpoint-url http://localhost:7070 \
  s3 ls s3://uro-uploads/ --recursive | head -10
```

Confirm the manifest record in CockroachDB:

```sh
docker exec multiplayer-fabric-hosting-crdb-1 \
  /cockroach/cockroach sql --insecure \
  -e "SELECT id, name, inserted_at FROM vsekai.shared_files ORDER BY inserted_at DESC LIMIT 3;"
```

## REFACTOR

If `AriaStorage.process_file/2` is not yet available in the zone_console
deps, add `{:aria_storage, github: "V-Sekai-fire/aria-storage"}` to
`mix.exs` and configure it in `config/runtime.exs`:

```elixir
import Config
config :aria_storage,
  storage_backend: :s3,
  s3_bucket:            System.get_env("AWS_S3_BUCKET",    "uro-uploads"),
  s3_endpoint:          System.get_env("AWS_S3_ENDPOINT",  "http://localhost:7070"),
  aws_access_key_id:    System.get_env("AWS_ACCESS_KEY_ID"),
  aws_secret_access_key: System.get_env("AWS_SECRET_ACCESS_KEY")
```

## Cloudflare Tunnel note

`POST /storage` goes through the tunnel. `POST /storage/:id` and the actual
chunk PUT to VersityGW are direct (bypassing Cloudflare). Cloudflare must not
cache POST requests. Confirm:

```sh
curl -sI -X POST https://hub-700a.chibifire.com/storage \
  -H "Authorization: Bearer $TOKEN" | grep -i cf-cache-status
# must be DYNAMIC or MISS, never HIT
```

If HIT appears, add a Cloudflare Cache Rule: match `URI Path starts with
/storage`, Cache Status = Bypass.
