# Upside-Down RED-GREEN-REFACTOR TDD: Cycles 6-8

**Status:** RED phase (18 failing tests)
**Cycles covered:** 6 (Godot zone handler), 7 (round-trip smoke test), 8 (native multi-platform)

## What is Upside-Down TDD?

Traditional TDD: Write code → Write tests → Refactor
**Upside-Down TDD:** Write integration tests FIRST → Watch them FAIL (RED) → Implement code (GREEN) → Refactor if needed

**Why?** The test IS the contract. It defines exactly what the system must do. Implementation follows the test's shape, not the other way around.

## Current Status: RED (18 failing tests)

All tests are written and failing. They define the complete contract for:
- Cycle 6: Authority zone instance pipeline
- Cycle 7: Round-trip smoke test
- Cycle 8: Native multi-platform verification

### Test Modules

```
test/multiplayer_fabric_deploy/zone_asset_streaming_integration_test.exs
  ├─ Cycle 6: CMD_INSTANCE_ASSET zone handler (12 tests)
  │  ├─ authority zone receives CMD_INSTANCE_ASSET
  │  ├─ fetch_manifest from uro
  │  ├─ download_chunks via casync
  │  ├─ sha_verify all chunks
  │  ├─ sandbox_load (RISC-V boundary)
  │  ├─ structural_verify (root type, node count, no external refs)
  │  ├─ instantiate at position
  │  ├─ broadcast_interest_ghost
  │  └─ authority invariants (2 tests)
  │
  ├─ Cycle 7: Round-trip smoke test (2 tests)
  │  ├─ full pipeline: upload → instance → entity list
  │  └─ authority zone logs verification
  │
  └─ Cycle 8: Native multi-platform (4 tests)
     ├─ WebTransport client connects on all platforms
     ├─ entity appears in zone list on all platforms
     ├─ AccessKit tree reflects instanced nodes
```

## Implementation Tasks (GREEN phase)

### Task 1: Implement InstancePipeline (Cycle 6 core)

**File:** `lib/multiplayer_fabric_deploy/zone_asset/instance_pipeline.ex`

Implement these functions in order:

#### 1.1 `fetch_manifest(asset_id, uro_url)`
- Call uro manifest endpoint: `GET /api/assets/{asset_id}/manifest`
- Returns map with `%{"chunks" => [...]}`
- Certificate pinning required (WebTransport)

#### 1.2 `download_chunks(manifest, store_path)`
- Use casync to download chunks (existing in FabricMMOGAsset)
- Store in `/tmp/scene-store/{chunk_id}`
- Return `:ok` when all chunks present

#### 1.3 `sha_verify(chunks, manifest)`
- Compute SHA-512/256 for each chunk
- Compare against manifest `sha512_256` field
- Return `:ok` or `{:error, :sha_mismatch}`

#### 1.4 `sandbox_load(scene_path)`
- Call Godot Sandbox with scene path
- Returns scene object with metadata: `%{source: :sandbox, scripted: true, ...}`
- Scripts execute INSIDE RISC-V VM (not in zone process)

#### 1.5 `structural_verify(scene, opts)`
- Check `root_node_type` is in allowed set (Node3D, Node2D, Control, etc.)
- Check `node_count` ≤ `opts[:max_nodes]` (default 10,000)
- Check `has_external_refs` == false
- Return `:ok` or appropriate `{:error, reason}` (see test cases)

#### 1.6 `instantiate(scene, pos)`
- Call Godot's `Node::add_child()` with scene at `{x, y, z}`
- Return node with `%{position: pos, parent_node_id: :scene_root, state: :active}`

#### 1.7 `broadcast_interest_ghost(hilbert_cell, pos)`
- Send CH_INTEREST message to zones within AOI_CELLS of hilbert_cell
- Include `%{message_type: :ch_interest, entity_id: uuid, position: pos, replica_type: :ghost}`

### Task 2: Implement AuthorityInvariant (Cycle 6 routing)

**File:** `lib/multiplayer_fabric_deploy/zone_asset/authority_invariant.ex`

#### 2.1 `verify_authority(receiving_zone, authority_zone, command, pos)`
- Returns `:ok` if `receiving_zone == authority_zone`
- Returns `{:error, :forward_to_authority}` otherwise
- Used in zone packet dispatcher: if forward, send to authority; if execute, run pipeline

**Hilbert routing:** Authority zone is determined by `hilbert_3d(pos)` — the 3D Hilbert curve position determines which zone owns the space.

### Task 3: Implement ZoneAsset high-level API (Cycle 7 smoke test)

**File:** `lib/multiplayer_fabric_deploy/zone_asset.ex`

#### 3.1 `upload_scene(zone_url, scene_path, opts)`
- Read raw scene file (`.tscn` or `.glb`)
- Chunk via casync
- POST chunks to uro: `POST /api/assets/upload`
- Return `{:ok, %{asset_id: uuid}}`

#### 3.2 `get_manifest(uro_url, asset_id)`
- Call uro: `GET /api/assets/{asset_id}/manifest`
- Return manifest map

#### 3.3 `send_instance_command(zone_url, asset_id, pos, opts)`
- Build CMD_INSTANCE_ASSET packet
- Send to zone server at zone_url with cert pinning
- Return `:ok` when acked

#### 3.4 `poll_entity_list(zone_url, opts)`
- Query zone server: `GET /api/entities`
- Return entity list with positions, asset_ids, replica_type

#### 3.5 `fetch_zone_logs()`
- Poll zone server logs
- Filter for "CMD_INSTANCE_ASSET", "authority", zone IDs
- Used for verifying correct zone handled packet

### Task 4: Implement WebTransportClient (Cycle 8 multi-platform)

**File:** `lib/multiplayer_fabric_deploy/zone_asset/web_transport_client.ex`

#### 4.1 `connect(zone_url, opts)`
- Use picoquic native backend for platform (macOS, Windows, Linux)
- Perform certificate pinning: `opts[:cert_pin]`
- Return `%{platform: platform, connected: true, ...}`

#### 4.2 `upload(client, scene_path)`
- Upload scene via WebTransport
- Return `{:ok, %{asset_id: uuid}}`

#### 4.3 `send_instance_command(client, asset_id, pos)`
- Send CMD_INSTANCE_ASSET via WebTransport
- Return `:ok` when acked

#### 4.4 `get_entity_list(client)`
- Fetch entity list via WebTransport
- Return entity list

### Task 5: Implement AccessKit (Cycle 8 platform UI verification)

**File:** `lib/multiplayer_fabric_deploy/zone_asset/access_kit.ex`

#### 5.1 `get_tree(platform)`
- macOS: Query NSAccessibility framework for active windows
- Windows: Use UIA (UI Automation) COM interface
- Linux: Connect to AT-SPI2 bus
- Return tree as map with node labels and positions
- Used to verify instanced nodes appear in native UI trees

## Test Execution

Run all 18 tests:

```bash
cd /Users/ernest.lee/Desktop/multiplayer-fabric/multiplayer-fabric-deploy
mix test test/multiplayer_fabric_deploy/zone_asset_streaming_integration_test.exs
```

Current: `18 failures`
Target: `18 passes`

## Implementation Order (Recommended)

1. **InstancePipeline** (7 functions) — Core cycle 6 logic
2. **AuthorityInvariant** (1 function) — Routing invariant
3. **ZoneAsset** (5 functions) — High-level API for smoke test
4. **WebTransportClient** (4 functions) — Platform clients
5. **AccessKit** (1 function) — UI tree verification

## Dependencies

- picoquic (WebTransport native)
- casync (chunk download)
- uro API (manifest, upload)
- Godot Sandbox (RISC-V)
- taskweft (orchestration)

## Next Steps After GREEN

Once all tests pass (GREEN):

1. **Refactoring** (REFACTOR): Extract common patterns, add error handling
2. **Integration with uro**: Wire up actual FLAME baking pipeline
3. **Integration with zone server**: Wire up Godot instance handler
4. **Cycle 7 manual smoke test**: Run through zone_console CLI
5. **Cycle 8 platform testing**: Test on macOS, Windows, Linux with AccessKit

## Notes

- Tests are marked `async: false` because zone network is stateful
- Hilbert 3D function is stubbed; use actual implementation from multiplayer-fabric-taskweft
- Environment variables used: `ZONE_SERVER_URL`, `URO_MANIFEST_URL`, `ZONE_CERT_PIN`, `TEST_SCENE_PATH`
- Some tests require running zone network (docker compose or FLAME stack)

---

**Test file:** `test/multiplayer_fabric_deploy/zone_asset_streaming_integration_test.exs`
**Module stubs:** `lib/multiplayer_fabric_deploy/zone_asset/*.ex`
