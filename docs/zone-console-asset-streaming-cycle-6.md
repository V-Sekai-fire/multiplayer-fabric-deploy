# Cycle 6 — Godot zone: handle CMD_INSTANCE_ASSET

**Status:** [ ] not started  
**Effort:** High  
**Back:** [index](zone-console-asset-streaming.md)

## What you get

The authority zone process receives `CMD_INSTANCE_ASSET`, fetches the scene
from S3 via the uro manifest, verifies chunk hashes, and instances the scene
at the requested position.

## macOS note

The Godot zone process runs inside the `zone-server` Docker container (Linux).
Build and test changes via:

```sh
docker compose build zone-server && docker compose up -d zone-server
```

There is no native macOS zone-server binary.

## Implementation

In `multiplayer-fabric-godot` — `FabricMMOGPeer::_process_peer_packet`:

- Add `case CMD_INSTANCE_ASSET:` dispatch
- Extract `asset_id` (two u32 slots → UUID) and `pos` (three f32 slots)
- Evaluate `rebacCheck` (ReBAC gate): caller must hold at least `instanceMember`
  relation for `interact`; public relation suffices for `observe`
- Call `FabricMMOGAsset::fetch_asset` with the uro manifest URL
- On completion: `ResourceLoader::load()` + `Node::instantiate()` at `pos`

`FabricMMOGAsset::fetch_asset` already handles the caibx index + chunk
download + SHA-512/256 verification pipeline.

## Authority invariant

Only the zone whose Hilbert range contains `hilbert3D(pos)` may execute this
handler.  If a `CMD_INSTANCE_ASSET` packet arrives at a non-authority zone,
it must be forwarded to the authority zone, not executed locally.

## Interest broadcast

After instancing, the authority zone broadcasts a CH_INTEREST ghost update for
the new node to all zones within `AOI_CELLS`.  Interest zones add it as a
`RelReplica` — they do not re-instance.

## Pass condition

After `instance <id> 0.0 1.0 0.0` from the console, the authority zone's
entity list shows a new entry at `(0.0, 1.0, 0.0)` and neighbouring interest
zones receive the CH_INTEREST ghost within one RTT.
