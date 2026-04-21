# Cycle 3 — `UroClient.get_manifest/2`

**Status:** [ ] RED  
**Effort:** Low  
**Back:** [index](zone-console-asset-streaming.md)  
**Depends on:** Cycle 2

## What you get

`UroClient.get_manifest/2` fetches the casync chunk manifest for a previously
uploaded asset. The manifest contains `store_url` (Tigris prefix) and `chunks`
(list of SHA-512/256 hashes). The zone server's C++ pipeline consumes this to
download and verify scene chunks.

## RED — failing test

File: `test/zone_console/uro_client_manifest_test.exs`

```elixir
defmodule ZoneConsole.UroClientManifestTest do
  use ExUnit.Case, async: false

  setup do
    client =
      ZoneConsole.UroClient.new(System.fetch_env!("URO_BASE_URL"))
      |> then(fn c ->
        {:ok, authed} = ZoneConsole.UroClient.login(c,
          System.fetch_env!("URO_EMAIL"),
          System.fetch_env!("URO_PASSWORD"))
        authed
      end)

    scene_path = System.fetch_env!("TEST_SCENE_PATH")
    {:ok, id} = ZoneConsole.UroClient.upload_asset(client, scene_path, Path.basename(scene_path))
    {:ok, %{client: client, id: id}}
  end

  @tag :prod
  test "get_manifest returns store_url and non-empty chunk list", %{client: client, id: id} do
    {:ok, manifest} = ZoneConsole.UroClient.get_manifest(client, id)

    assert is_binary(manifest["store_url"]) or is_binary(manifest[:store_url])
    chunks = manifest["chunks"] || manifest[:chunks]
    assert is_list(chunks)
    assert length(chunks) > 0
  end

  @tag :prod
  test "each chunk entry has an id and sha512_256 hash", %{client: client, id: id} do
    {:ok, manifest} = ZoneConsole.UroClient.get_manifest(client, id)
    chunks = manifest["chunks"] || manifest[:chunks]

    Enum.each(chunks, fn chunk ->
      id_val  = chunk["id"]  || chunk[:id]
      sha_val = chunk["sha512_256"] || chunk[:sha512_256]
      assert is_binary(id_val),  "chunk must have binary id"
      assert is_binary(sha_val), "chunk must have sha512_256"
      assert byte_size(sha_val) == 64, "SHA-512/256 hex must be 64 chars"
    end)
  end
end
```

Run with the same env vars as Cycle 2.

## GREEN — pass condition

Both tests pass against `https://uro.chibifire.com`. Each chunk entry carries
a 64-character hex SHA-512/256 string.

Verify the manifest endpoint directly:

```sh
TOKEN=$(curl -s -X POST https://uro.chibifire.com/session \
  -H "Content-Type: application/json" \
  -d '{"user":{"email":"<email>","password":"<pw>"}}' | jq -r '.data.access_token')

curl -s -X POST https://uro.chibifire.com/storage/<id>/manifest \
  -H "Authorization: Bearer $TOKEN" | jq .
```

## REFACTOR

If `get_manifest` uses `POST /storage/:id/manifest`, confirm the Cloudflare
Page Rule for `POST /storage*` bypasses cache. A cached 200 on a manifest
POST would return stale chunk lists.

```sh
curl -sI -X POST https://uro.chibifire.com/storage/<id>/manifest \
  -H "Authorization: Bearer $TOKEN" | grep cf-cache-status
# Must be MISS or DYNAMIC, never HIT
```
