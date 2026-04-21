# Cycle 2 — `UroClient.upload_asset/3`

**Status:** [ ] RED  
**Effort:** Medium  
**Back:** [index](zone-console-asset-streaming.md)  
**Depends on:** Cycle 1

## What you get

`UroClient.upload_asset/3` chunks a local scene file via AriaStorage, uploads
the chunks to Tigris (Fly.io S3), and registers a manifest entry in uro.
Returns `{:ok, id}` where `id` is the asset UUID.

## Infrastructure

Chunks land in Tigris bucket `uro-uploads` via `AWS_S3_ENDPOINT=https://fly.storage.tigris.dev`.
Tigris is Fly.io-native and includes global CDN at no egress cost. The uro
backend at `https://uro.chibifire.com` records the manifest (name, chunks,
store_url) in CockroachDB.

## RED — failing test

File: `test/zone_console/uro_client_upload_test.exs`

```elixir
defmodule ZoneConsole.UroClientUploadTest do
  use ExUnit.Case, async: false

  @tag :prod
  test "upload_asset stores file and returns non-empty id" do
    client =
      ZoneConsole.UroClient.new(System.fetch_env!("URO_BASE_URL"))
      |> then(fn c ->
        {:ok, authed} = ZoneConsole.UroClient.login(c,
          System.fetch_env!("URO_EMAIL"),
          System.fetch_env!("URO_PASSWORD"))
        authed
      end)

    scene_path = System.fetch_env!("TEST_SCENE_PATH")
    name = Path.basename(scene_path)

    {:ok, id} = ZoneConsole.UroClient.upload_asset(client, scene_path, name)

    assert is_binary(id)
    assert byte_size(id) > 0
  end

  @tag :prod
  test "uploaded asset is queryable via GET /storage/:id" do
    client =
      ZoneConsole.UroClient.new(System.fetch_env!("URO_BASE_URL"))
      |> then(fn c ->
        {:ok, authed} = ZoneConsole.UroClient.login(c,
          System.fetch_env!("URO_EMAIL"),
          System.fetch_env!("URO_PASSWORD"))
        authed
      end)

    scene_path = System.fetch_env!("TEST_SCENE_PATH")
    name = Path.basename(scene_path)
    {:ok, id} = ZoneConsole.UroClient.upload_asset(client, scene_path, name)

    # Asset must be retrievable
    {:ok, %{status: 200}} =
      Req.get("#{System.fetch_env!("URO_BASE_URL")}/storage/#{id}",
        headers: [{"authorization", "Bearer #{client.access_token}"}])
  end
end
```

Run with:

```sh
cd multiplayer-fabric-zone-console
URO_BASE_URL=https://uro.chibifire.com \
URO_EMAIL=... \
URO_PASSWORD=... \
TEST_SCENE_PATH=../multiplayer-fabric-humanoid-project/humanoid/scenes/mire.tscn \
AWS_S3_BUCKET=uro-uploads \
AWS_S3_ENDPOINT=https://fly.storage.tigris.dev \
AWS_ACCESS_KEY_ID=... \
AWS_SECRET_ACCESS_KEY=... \
mix test --only prod test/zone_console/uro_client_upload_test.exs
```

## GREEN — pass condition

Both tests pass. The asset id is a UUID string. `GET /storage/:id` returns
HTTP 200 with the asset record.

Verify the chunk landed in Tigris:

```sh
fly storage ls uro-uploads --app multiplayer-fabric-uro
```

## REFACTOR

`UroClient.upload_asset/3` is implemented in `uro_client.ex` via
`AriaStorage.process_file/2`. If AriaStorage is not yet a hard dep, gate it
with `Code.ensure_loaded?(AriaStorage)` so the console compiles without it in
dev environments where Tigris creds are absent.

## Fly.io + Cloudflare checks

```sh
# Fly.io: confirm POST /storage reached the machine
fly logs --app multiplayer-fabric-uro | grep "POST /storage"

# Cloudflare: confirm cache status (Storage writes must be MISS, not HIT)
curl -sI https://uro.chibifire.com/storage/<id> | grep cf-cache-status
```

Cloudflare must not cache POST requests. If `cf-cache-status: HIT` appears on
a POST, add a Page Rule to bypass cache for `/storage*` POST methods.
