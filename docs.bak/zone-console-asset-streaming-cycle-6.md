# Cycle 6 — Godot zone: handle CMD_INSTANCE_ASSET

**Status:** [/] Elixir pipeline implemented and tested (18/18 tests green); Godot C++ zone handler pending  
**Effort:** High  
**Back:** [index](zone-console-asset-streaming.md)

## What you get

The authority zone receives `CMD_INSTANCE_ASSET`, runs a taskweft pipeline to
fetch, verify, and sandbox-load the scene, then instantiates it at the
requested position.

## macOS note

The Godot zone process runs inside the `zone-server` Docker container (Linux).
Build and test changes via:

```sh
docker compose build zone-server && docker compose up -d zone-server
```

There is no native macOS zone-server binary.

## Design

`zone_console` is a dumb uploader — it sends the raw scene and all its
dependency chunks to uro with no pre-processing.  All safety is enforced at
load time on the zone server.

The **Godot Sandbox** (RISC-V VM) is the clean boundary.  Scripts in the
uploaded scene run inside the VM regardless of content — no whitelist
pre-processing needed, no Godot binary dependency outside the zone server.

**Taskweft** (Elixir/C++20 NIFs, 93 PropCheck properties) orchestrates the
ingestion pipeline as a task graph.

## Taskweft pipeline

```
fetch_manifest        fetch chunk list from uro manifest URL
  → download_chunks   casync download of all chunks (scene + dependencies)
  → sha_verify        SHA-512/256 hash check per chunk (existing in FabricMMOGAsset)
  → sandbox_load      ResourceLoader::load() inside Godot Sandbox
  → structural_verify root node type valid, node count sane, no external refs
  → instantiate       Node::add_child() at pos, broadcast CH_INTEREST ghost
```

Each step is a discrete taskweft task.  Failure at any step aborts the
pipeline and returns an error packet to the sender.

## Implementation

In `multiplayer-fabric-godot` — `FabricMMOGPeer::_process_peer_packet`:

- Add `case CMD_INSTANCE_ASSET:` dispatch
- Extract `asset_id` (two u32 slots → UUID) and `pos` (three f32 slots)
- Evaluate `rebacCheck`: caller must hold at least `instanceMember` for
  `interact`; public relation suffices for `observe`
- Hand off to `FabricMMOGAsset::run_instance_pipeline(asset_id, pos)`

`FabricMMOGAsset::run_instance_pipeline`:

1. `fetch_manifest` — call uro manifest URL via `UroClient::get_manifest`
2. `download_chunks` — casync chunk download (existing `fetch_asset` logic)
3. `sha_verify` — SHA-512/256 per chunk (existing)
4. `sandbox_load` — `Sandbox::create_from_path(scene_path)` — RISC-V VM
   boundary replaces VSK script-cleaning; scene scripts execute inside VM
5. `structural_verify` — check root node type is in allowed set, node count
   ≤ `MAX_ASSET_NODES`, no `res://` external refs in packed resource
6. `instantiate` — `Node::add_child()` at `pos`

## Authority invariant

Only the zone whose Hilbert range contains `hilbert3D(pos)` executes this
pipeline.  A `CMD_INSTANCE_ASSET` arriving at a non-authority zone is
forwarded, not executed locally.

## Interest broadcast

After instantiation the authority zone broadcasts a `CH_INTEREST` ghost update
to all zones within `AOI_CELLS`.  Interest zones add it as a `RelReplica` —
they do not re-run the pipeline.

## Pass condition

After `instance <id> 0.0 1.0 0.0` from the console, the authority zone entity
list shows a new entry at `(0.0, 1.0, 0.0)` and neighbouring interest zones
receive the `CH_INTEREST` ghost within one RTT.
