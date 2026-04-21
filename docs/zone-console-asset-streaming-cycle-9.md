# Cycle 9 — Round-trip smoke test

**Status:** [ ] RED  
**Effort:** High  
**Back:** [index](zone-console-asset-streaming.md)  
**Depends on:** Cycle 8

## What you get

A single test session exercises the full pipeline end-to-end on the live
stack: login → upload → wait for bake → instance → entity list confirmed.
No mocks. No stubs. Every hop verifiable in Docker logs.

## Infrastructure path (full round-trip)

```
zone_console
  1. login        → HTTPS → Cloudflare Tunnel → zone-backend:4000
  2. upload_asset → AriaStorage → versitygw:7070 (direct)
                  → HTTPS → Cloudflare Tunnel → zone-backend:4000 (manifest)
  3. baker        → Docker one-shot → versitygw:7070 → baked_url in DB
  4. send_instance → WebTransport UDP 443 → zone-server (direct, no CF)
  5. entity_list  ← WebTransport entity snapshot from zone-server
```

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
Baking... (polling every 2 s)
Baked. baked_url = http://localhost:7070/uro-uploads/550e8400-....tar.gz

> join 0
Joined zone 0 at zone-700a.chibifire.com:443

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

  defp authed_client do
    ZoneConsole.UroClient.new(System.fetch_env!("URO_BASE_URL"))
    |> then(fn c ->
      {:ok, a} = ZoneConsole.UroClient.login(c,
        System.fetch_env!("URO_EMAIL"), System.fetch_env!("URO_PASSWORD"))
      a
    end)
  end

  @tag :prod
  test "full pipeline: login → upload → bake → instance → entity list" do
    client     = authed_client()
    scene_path = System.fetch_env!("TEST_SCENE_PATH")
    {:ok, id}  = ZoneConsole.UroClient.upload_asset(client, scene_path,
      Path.basename(scene_path))

    # Poll for bake (max 30 s)
    baked_url =
      Enum.find_value(1..30, fn _ ->
        {:ok, m} = ZoneConsole.UroClient.get_manifest(client, id)
        url = m["baked_url"] || m[:baked_url]
        if url, do: url, else: (Process.sleep(1_000); nil)
      end)

    assert is_binary(baked_url), "baked_url must appear within 30 s"

    url = System.fetch_env!("ZONE_SERVER_URL")
    pin = System.fetch_env!("ZONE_CERT_PIN")
    {:ok, zc} = ZoneConsole.ZoneClient.start_link(url, pin, 1, self())

    ZoneConsole.ZoneClient.send_instance(zc, String.to_integer(id), 0.0, 1.0, 0.0)

    assert_receive {:zone_entities, entities}, 2_000

    found = Enum.any?(Map.values(entities), fn e -> abs(e.cy - 1.0) < 0.5 end)
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
URO_EMAIL=... URO_PASSWORD=... \
TEST_SCENE_PATH=../multiplayer-fabric-humanoid-project/humanoid/scenes/mire.tscn \
AWS_S3_BUCKET=uro-uploads AWS_S3_ENDPOINT=http://localhost:7070 \
AWS_ACCESS_KEY_ID=minioadmin AWS_SECRET_ACCESS_KEY=minioadmin \
mix test --only prod test/zone_console/round_trip_test.exs
```

## GREEN — pass condition

Test passes end-to-end. Under 35 s total.

Full stack verification:

```sh
# 1. Cloudflare Tunnel healthy (4 edge connections)
docker logs multiplayer-fabric-hosting-cloudflared-1 2>&1 | \
  grep "Registered tunnel" | wc -l

# 2. CockroachDB has the asset record with baked_url set
docker exec multiplayer-fabric-hosting-crdb-1 \
  /cockroach/cockroach sql --insecure \
  -e "SELECT id, name, baked_url IS NOT NULL FROM vsekai.shared_files \
      ORDER BY inserted_at DESC LIMIT 3;"

# 3. VersityGW has both raw chunks and baked tarball
AWS_ACCESS_KEY_ID=minioadmin AWS_SECRET_ACCESS_KEY=minioadmin \
  aws --endpoint-url http://localhost:7070 s3 ls s3://uro-uploads/ --recursive

# 4. Zone server entity list
docker logs multiplayer-fabric-hosting-zone-server-1 2>&1 | \
  grep -E "instantiate|CH_INTEREST"
```

## REFACTOR

Extract the poll-for-baked-url logic into `ZoneConsole.TestHelpers.poll/3`
and reuse it in Cycle 10.
