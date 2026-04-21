# Cycle 8 — Godot zone handler

**Status:** [ ] RED  
**Effort:** High  
**Back:** [index](zone-console-asset-streaming.md)  
**Depends on:** Cycles 6, 7

## What you get

The authority zone's C++ process receives `CMD_INSTANCE_ASSET`, runs the
taskweft pipeline (fetch → verify → sandbox_load → instantiate), and
broadcasts a `CH_INTEREST` ghost to neighbouring zones. The Elixir deploy
library wires the pipeline steps.

## Pipeline (zone server side)

```
FabricMMOGPeer::_process_peer_packet (C++)
  case CMD_INSTANCE_ASSET:
    → extract asset_id (two u32 slots), pos (three f32 slots)
    → rebacCheck: caller needs instanceMember or owner
    → FabricMMOGAsset::run_instance_pipeline(asset_id, pos)

run_instance_pipeline:
  1. fetch_manifest   GET /storage/:id/manifest (via UroClient NIF)
  2. download_chunks  casync pull from Tigris store_url
  3. sha_verify       SHA-512/256 per chunk
  4. sandbox_load     Sandbox::create_from_path(scene_path)  ← RISC-V VM
  5. structural_verify root_node_type ∈ allowed, node_count ≤ 10k, no res:// refs
  6. instantiate      Node::add_child() at pos
  7. broadcast        CH_INTEREST ghost to AOI_CELLS neighbours
```

Authority rule: only the zone whose Hilbert range contains `hilbert3D(pos)`
executes this pipeline. A `CMD_INSTANCE_ASSET` arriving at a non-authority
zone is forwarded, not executed locally.

## RED — failing tests

File: `test/multiplayer_fabric_deploy/zone_asset_streaming_integration_test.exs`
(already exists — 18 tests that exercise the Elixir side of the pipeline)

For the C++ side, the pass condition is a live zone server log entry. The
Elixir tests below verify the routing and pipeline contracts before the C++
handler is wired:

```elixir
# Existing tests already cover:
#   structural_verify — 4 cases (valid, bad root type, too many nodes, external refs)
#   authority_invariant — authority executes, non-authority does not
#   broadcast_interest_ghost — returns {:ok, %{message_type: :ch_interest, ...}}
#   instantiate — returns {:ok, %{position: pos, state: :active}}
#
# New test needed for the full C++ dispatch path (requires live zone server):

@tag :prod
test "CMD_INSTANCE_ASSET arrives at authority zone and appears in entity list",
     %{zone_server_url: url, cert_pin: pin} do
  client =
    ZoneConsole.UroClient.new(System.fetch_env!("URO_BASE_URL"))
    |> then(fn c ->
      {:ok, a} = ZoneConsole.UroClient.login(c,
        System.fetch_env!("URO_EMAIL"), System.fetch_env!("URO_PASSWORD"))
      a
    end)

  scene_path = System.fetch_env!("TEST_SCENE_PATH")
  {:ok, asset_id} = ZoneConsole.UroClient.upload_asset(client, scene_path,
    Path.basename(scene_path))

  # Wait for baker
  {:ok, manifest} = poll_for_baked_url(client, asset_id, 30)

  # Send instance command
  {:ok, zone_client} = ZoneConsole.ZoneClient.start_link(url, pin, 1, self())
  ZoneConsole.ZoneClient.send_instance(zone_client, String.to_integer(asset_id),
    0.0, 1.0, 0.0)

  # Expect entity snapshot containing the new node
  assert_receive {:zone_entities, entities}, 2_000
  assert Map.values(entities) |> Enum.any?(fn e ->
    abs(e.cy - 1.0) < 0.1
  end), "entity should appear near y=1.0"

  ZoneConsole.ZoneClient.stop(zone_client)
end
```

Run with:

```sh
cd multiplayer-fabric-zone-console
URO_BASE_URL=https://uro.chibifire.com \
ZONE_SERVER_URL=https://zone-700a.chibifire.com \
ZONE_CERT_PIN=... URO_EMAIL=... URO_PASSWORD=... \
TEST_SCENE_PATH=../multiplayer-fabric-humanoid-project/humanoid/scenes/mire.tscn \
AWS_S3_BUCKET=uro-uploads AWS_S3_ENDPOINT=https://fly.storage.tigris.dev \
AWS_ACCESS_KEY_ID=... AWS_SECRET_ACCESS_KEY=... \
mix test --only prod
```

## GREEN — pass condition

The new prod test passes. Zone server logs show:

```
CMD_INSTANCE_ASSET received asset=<id> pos=(0.0,1.0,0.0)
authority check: zone 0 is authority for hilbert=...
pipeline: fetch_manifest OK
pipeline: sha_verify OK
pipeline: sandbox_load OK
pipeline: structural_verify OK
pipeline: instantiate OK pos=(0.0,1.0,0.0)
pipeline: broadcast CH_INTEREST to 0 neighbours
```

## REFACTOR

After green, collapse `run_instance_pipeline` steps 1-3 into a
`FabricMMOGAsset::fetch_and_verify(asset_id)` method that returns a
scene_path or error. This isolates network I/O from the verification logic
and makes each step independently unit-testable.

## Fly.io rebuild

```sh
# rebuild zone server image with C++ CMD_INSTANCE_ASSET handler
cd multiplayer-fabric-godot
docker build --target zone-server \
  -t registry.fly.io/multiplayer-fabric-zones:latest .
fly auth docker
docker push registry.fly.io/multiplayer-fabric-zones:latest
fly deploy --app multiplayer-fabric-zones
fly logs --app multiplayer-fabric-zones
```
