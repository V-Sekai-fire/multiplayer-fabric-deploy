# Cycle 3 — `UroClient.get_manifest/2`

**Status:** [ ] RED  
**Effort:** Low  
**Back:** [index](zone-console-asset-streaming.md)  
**Depends on:** Cycle 2

## What you get

`UroClient.get_manifest/2` fetches the casync chunk manifest for a previously
uploaded asset. The manifest contains `store_url` (VersityGW prefix) and
`chunks` (list of SHA-512/256 hashes). The zone server's C++ pipeline
consumes this to download and verify scene chunks.

## Infrastructure path

```
zone_console (macOS)
  → HTTPS POST /storage/:id/manifest
  → Cloudflare Tunnel → zone-backend:4000
  → CockroachDB lookup
  → returns {store_url, chunks}
```

## RED — failing test

File: `test/zone_console/uro_client_manifest_test.exs`

```elixir
defmodule ZoneConsole.UroClientManifestTest do
  use ExUnit.Case, async: false

  setup do
    client =
      ZoneConsole.UroClient.new(System.fetch_env!("URO_BASE_URL"))
      |> then(fn c ->
        {:ok, a} = ZoneConsole.UroClient.login(c,
          System.fetch_env!("URO_EMAIL"),
          System.fetch_env!("URO_PASSWORD"))
        a
      end)

    scene_path = System.fetch_env!("TEST_SCENE_PATH")
    {:ok, id}  = ZoneConsole.UroClient.upload_asset(client, scene_path,
      Path.basename(scene_path))

    {:ok, %{client: client, id: id}}
  end

  @tag :prod
  test "get_manifest returns store_url and non-empty chunk list", %{client: c, id: id} do
    {:ok, manifest} = ZoneConsole.UroClient.get_manifest(c, id)

    store_url = manifest["store_url"] || manifest[:store_url]
    chunks    = manifest["chunks"]    || manifest[:chunks]

    assert is_binary(store_url), "manifest must have store_url"
    assert is_list(chunks),      "manifest must have chunks list"
    assert length(chunks) > 0,   "chunks must not be empty"
  end

  @tag :prod
  test "each chunk has id and 64-char sha512_256 hex", %{client: c, id: id} do
    {:ok, manifest} = ZoneConsole.UroClient.get_manifest(c, id)
    chunks = manifest["chunks"] || manifest[:chunks]

    Enum.each(chunks, fn chunk ->
      chunk_id = chunk["id"]         || chunk[:id]
      sha      = chunk["sha512_256"] || chunk[:sha512_256]
      assert is_binary(chunk_id),          "chunk id must be binary"
      assert is_binary(sha),               "chunk sha512_256 must be binary"
      assert byte_size(sha) == 64,         "SHA-512/256 hex must be 64 chars"
    end)
  end
end
```

Run with the same env vars as Cycle 2.

## GREEN — pass condition

Both tests pass against `https://hub-700a.chibifire.com`. The `store_url`
points to the VersityGW prefix on `localhost:7070`.

Verify directly:

```sh
TOKEN=$(curl -s -X POST https://hub-700a.chibifire.com/session \
  -H "Content-Type: application/json" \
  -d '{"user":{"email":"...","password":"..."}}' | python3 -c \
  "import sys,json; print(json.load(sys.stdin)['data']['access_token'])")

curl -s -X POST https://hub-700a.chibifire.com/storage/<id>/manifest \
  -H "Authorization: Bearer $TOKEN" | python3 -m json.tool
```

## REFACTOR

The `get_manifest/2` implementation in `uro_client.ex` uses
`POST /storage/:id/manifest`. If the response shape differs from what the
C++ zone pipeline expects (it reads `store_url` and a flat `chunks` list),
add an adapter in the Elixir layer rather than changing the Phoenix
controller.

## Cloudflare Tunnel note

`POST /storage/:id/manifest` must reach the zone-backend — confirm no
cached response from Cloudflare:

```sh
curl -sI -X POST https://hub-700a.chibifire.com/storage/<id>/manifest \
  -H "Authorization: Bearer $TOKEN" | grep -i cf-cache-status
# expect DYNAMIC or MISS
```
