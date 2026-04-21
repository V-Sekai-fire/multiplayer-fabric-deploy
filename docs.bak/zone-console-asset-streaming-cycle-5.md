# Cycle 5 — UroClient.get_manifest/2

**Status:** [x] done  
**Effort:** Low  
**Back:** [index](zone-console-asset-streaming.md)

## What you get

`UroClient.get_manifest/2` fetches the casync chunk manifest for an uploaded
asset so the zone server can download and verify the scene file.

## Implementation

`multiplayer-fabric-zone-console/lib/zone_console/uro_client.ex`:

- POST `/storage/:id/manifest`
- Returns `{:ok, %{store_url: _, chunks: [_|_]}}`

The manifest lists SHA-512/256 chunk hashes and the S3 store URL.
`FabricMMOGAsset::fetch_asset` on the C++ side consumes this manifest
to download and verify each chunk before loading the scene.

## Authority note

The authority zone (the one whose Hilbert range contains the target position)
calls `get_manifest` after receiving `CMD_INSTANCE_ASSET`.  Interest zones
never fetch the manifest; they receive ghost updates of the already-instanced
node via CH_INTEREST broadcast.

## Pass condition

`UroClient.get_manifest/2` returns `{:ok, %{store_url: <url>, chunks: [...]}}` with
at least one chunk hash for a previously uploaded asset.
