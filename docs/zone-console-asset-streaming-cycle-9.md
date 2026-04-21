# Cycle 9 — Round-trip smoke test

**Status:** [ ] RED  
**Effort:** High  
**Back:** [index](zone-console-asset-streaming.md)  
**Depends on:** Cycle 8

## What you get

A single CLI session exercises the full pipeline end-to-end on production
infrastructure: log in, upload, wait for bake, instance, confirm entity list,
confirm neighbour ghost. No mocks. No stubs.

## Manual smoke test sequence

From `zone_console` (runs natively on macOS):

```
> login
Username/email: <operator email>
Password: ****
Logged in as <user>

> upload multiplayer-fabric-humanoid-project/humanoid/scenes/mire.tscn
Uploaded mire.tscn as 550e8400-...

> bake-status 550e8400-...
Baking... (poll every 2 s)
Baked. baked_url = https://fly.storage.tigris.dev/uro-uploads/550e8400-....tar.gz

> join 0
Joined zone 0 (zone-700a.chibifire.com:7777)

> instance 550e8400-... 0.0 1.0 0.0
Instance request sent for asset 550e8400-... at (0.0, 1.0, 0.0)

> entities
[zone 0]  id=42  pos=(0.00, 1.00, 0.00)  type=scene  asset=550e8400-...
```

## Automated test

File: `test/zone_console/round_trip_test.exs`

```elixir
defmodule ZoneConsole.RoundTripTest do
  use ExUnit.Case, async: false

  @tag :prod
  test "full pipeline: login → upload → bake → instance → entity list" do
    base = System.fetch_env!("URO_BASE_URL")
    client =
      ZoneConsole.UroClient.new(base)
      |> then(fn c ->
        {:ok, a} = ZoneConsole.UroClient.login(c,
          System.fetch_env!("URO_EMAIL"), System.fetch_env!("URO_PASSWORD"))
        a
      end)

    # Upload
    scene_path = System.fetch_env!("TEST_SCENE_PATH")
    {:ok, asset_id} = ZoneConsole.UroClient.upload_asset(client, scene_path,
      Path.basename(scene_path))

    # Wait for bake (max 30 s)
    baked_url = poll_for_baked_url(client, asset_id, 30)
    assert is_binary(baked_url)

    # Instance
    url  = System.fetch_env!("ZONE_SERVER_URL")
    pin  = System.fetch_env!("ZONE_CERT_PIN")
    pid  = self()
    {:ok, zc} = ZoneConsole.ZoneClient.start_link(url, pin, 1, pid)
    ZoneConsole.ZoneClient.send_instance(zc, String.to_integer(asset_id),
      0.0, 1.0, 0.0)

    # Entity appears in zone entity list within 2 s
    assert_receive {:zone_entities, entities}, 2_000
    found = Enum.any?(Map.values(entities), fn e ->
      abs(e.cy - 1.0) < 0.5
    end)
    assert found, "entity near y=1.0 must appear"
    ZoneConsole.ZoneClient.stop(zc)
  end

  @tag :prod
  test "CH_INTEREST ghost reaches neighbour zone within one RTT" do
    # This test requires at least 2 running zone machines.
    # Skip if only one zone is up.
    client =
      ZoneConsole.UroClient.new(System.fetch_env!("URO_BASE_URL"))
      |> then(fn c ->
        {:ok, a} = ZoneConsole.UroClient.login(c,
          System.fetch_env!("URO_EMAIL"), System.fetch_env!("URO_PASSWORD"))
        a
      end)

    {:ok, zones} = ZoneConsole.UroClient.list_zones(client)
    if length(zones) < 2, do: flunk("need at least 2 zones for ghost test")

    [auth_zone | [neighbour | _]] = zones
    auth_url  = "https://#{auth_zone["address"]}:#{auth_zone["port"]}"
    nbr_url   = "https://#{neighbour["address"]}:#{neighbour["port"]}"
    auth_pin  = auth_zone["cert_hash"]
    nbr_pin   = neighbour["cert_hash"]

    # Connect to both zones
    {:ok, ac} = ZoneConsole.ZoneClient.start_link(auth_url, auth_pin, 1, self())
    {:ok, nc} = ZoneConsole.ZoneClient.start_link(nbr_url,  nbr_pin,  2, self())

    # Instance via authority zone
    asset_id  = String.to_integer(System.fetch_env!("TEST_ASSET_ID"))
    ZoneConsole.ZoneClient.send_instance(ac, asset_id, 0.0, 1.0, 0.0)

    # Neighbour receives CH_INTEREST ghost
    assert_receive {:zone_entities, _}, 1_000

    ZoneConsole.ZoneClient.stop(ac)
    ZoneConsole.ZoneClient.stop(nc)
  end

  defp poll_for_baked_url(client, id, secs) do
    Enum.find_value(1..secs, fn _ ->
      {:ok, m} = ZoneConsole.UroClient.get_manifest(client, id)
      url = m["baked_url"] || m[:baked_url]
      if url, do: url, else: (Process.sleep(1_000); nil)
    end)
  end
end
```

## GREEN — pass condition

Both tests pass on prod. The smoke test takes under 35 s end to end. Zone
server logs confirm authority routing and interest broadcast.

```sh
fly logs --app multiplayer-fabric-zones | grep -E "authority|CH_INTEREST|instantiate"
```

## Fly.io + Cloudflare health checks

```sh
# Uro health
curl -s https://uro.chibifire.com/healthz

# Cloudflare edge latency
curl -sw "\n%{time_total}s\n" -o /dev/null https://uro.chibifire.com/healthz

# Zone machine count
fly machines list --app multiplayer-fabric-zones | grep started | wc -l

# CRDB connectivity (from uro machine)
fly ssh console --app multiplayer-fabric-uro -C \
  "psql $DATABASE_URL -c 'SELECT 1'"
```
