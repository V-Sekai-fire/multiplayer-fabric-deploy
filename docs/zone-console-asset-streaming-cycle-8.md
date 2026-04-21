# Cycle 8 — Godot zone handler

**Status:** [ ] RED  
**Effort:** High  
**Back:** [index](zone-console-asset-streaming.md)  
**Depends on:** Cycles 6, 7

## What you get

The authority zone's C++ process receives `CMD_INSTANCE_ASSET`, runs the
taskweft pipeline (fetch_manifest → sha_verify → sandbox_load →
structural_verify → instantiate → broadcast_interest_ghost), and the new
entity appears in the zone entity list.

## Infrastructure path

```
zone_console
  → send_instance via WebTransport (UDP 443 direct)
  → zone-server (Docker, host machine)
      FabricMMOGPeer::_process_peer_packet
        case CMD_INSTANCE_ASSET:
          rebacCheck
          FabricMMOGAsset::run_instance_pipeline
            GET /storage/:id/manifest → hub-700a.chibifire.com (via Cloudflare Tunnel)
            download chunks from versitygw:7070 (direct Docker network)
            sha_verify
            Sandbox::create_from_path (RISC-V VM)
            structural_verify
            Node::add_child at pos
            broadcast CH_INTEREST ghost
```

The zone server calls `hub-700a.chibifire.com` for manifest fetches. Inside
Docker, `zone-backend` is reachable directly at `http://zone-backend:4000` —
the C++ client can use either the public hostname or the Docker service name.

## RED — failing test

The 18 Elixir-side tests in `multiplayer-fabric-deploy` already cover the
pipeline steps in isolation. The new test that requires a live zone server:

File: `test/zone_console/zone_handler_test.exs`

```elixir
defmodule ZoneConsole.ZoneHandlerTest do
  use ExUnit.Case, async: false

  @tag :prod
  test "CMD_INSTANCE_ASSET reaches authority zone and entity appears in list" do
    url      = System.fetch_env!("ZONE_SERVER_URL")
    pin      = System.fetch_env!("ZONE_CERT_PIN")
    asset_id = String.to_integer(System.fetch_env!("TEST_ASSET_ID"))

    {:ok, zc} = ZoneConsole.ZoneClient.start_link(url, pin, 1, self())
    ZoneConsole.ZoneClient.send_instance(zc, asset_id, 0.0, 1.0, 0.0)

    assert_receive {:zone_entities, entities}, 2_000

    found = Enum.any?(Map.values(entities), fn e ->
      abs(e.cy - 1.0) < 0.5
    end)
    assert found, "entity near y=1.0 must appear in zone entity list"

    ZoneConsole.ZoneClient.stop(zc)
  end
end
```

Run:

```sh
cd multiplayer-fabric-zone-console
URO_BASE_URL=https://hub-700a.chibifire.com \
ZONE_SERVER_URL=https://zone-700a.chibifire.com \
ZONE_CERT_PIN=<fingerprint> \
TEST_ASSET_ID=<id from Cycle 2> \
mix test --only prod test/zone_console/zone_handler_test.exs
```

## GREEN — pass condition

Test passes. Zone server Docker logs show the complete pipeline:

```sh
docker logs multiplayer-fabric-hosting-zone-server-1 2>&1 | \
  grep -E "CMD_INSTANCE_ASSET|fetch_manifest|sha_verify|sandbox_load|instantiate"
```

Expected log lines:

```
CMD_INSTANCE_ASSET received asset=<id> pos=(0.0,1.0,0.0)
authority check: zone 0 is authority for hilbert=...
pipeline: fetch_manifest OK
pipeline: sha_verify OK
pipeline: sandbox_load OK
pipeline: structural_verify OK
pipeline: instantiate OK pos=(0.0,1.0,0.0)
```

## Implementation

In `multiplayer-fabric-godot`:

1. `FabricMMOGPeer::_process_peer_packet` — add `case CMD_INSTANCE_ASSET:`
2. Extract `asset_id` from payload[1]/[2], `pos` from payload[3-5]
3. `rebacCheck(caller, "instanceMember")` — return error packet if denied
4. `FabricMMOGAsset::run_instance_pipeline(asset_id, pos)`

Rebuild the zone server Docker image and restart:

```sh
cd multiplayer-fabric-godot
docker build --target zone-server \
  -t multiplayer-fabric-godot-server:latest -f Dockerfile .

cd multiplayer-fabric-hosting
docker compose up -d zone-server
docker logs -f multiplayer-fabric-hosting-zone-server-1
```
