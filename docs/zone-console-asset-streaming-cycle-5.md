# Cycle 5 — `instance` console command

**Status:** [ ] RED  
**Effort:** Low  
**Back:** [index](zone-console-asset-streaming.md)  
**Depends on:** Cycles 1, 2, 4

## What you get

Running `instance <id> <x> <y> <z>` in `zone_console` sends a
`CMD_INSTANCE_ASSET` packet to the live zone server on Fly.io and receives an
ACK. This is the first cycle that requires a running zone server.

## Infrastructure

Zone server app `multiplayer-fabric-zones` on Fly.io listens on UDP 443
at `zone-700a.chibifire.com`. The console connects via native WebTransport
(picoquic). Certificate pinning uses `ZONE_CERT_PIN` — the SHA-256 fingerprint
of the zone server's self-signed cert printed on startup.

Cloudflare does not proxy UDP — zone server traffic bypasses Cloudflare and
reaches Fly.io directly.

## RED — failing test

File: `test/zone_console/instance_command_test.exs`

```elixir
defmodule ZoneConsole.InstanceCommandTest do
  use ExUnit.Case, async: false

  @tag :prod
  test "instance command reaches zone server and gets ACK" do
    url      = System.fetch_env!("ZONE_SERVER_URL")
    cert_pin = System.fetch_env!("ZONE_CERT_PIN")
    asset_id = System.fetch_env!("TEST_ASSET_ID")  # from a prior Cycle 2 upload

    player_id = :rand.uniform(0x7FFFFFFF)

    {:ok, client} = ZoneConsole.ZoneClient.start_link(url, cert_pin, player_id, self())

    ZoneConsole.ZoneClient.send_instance(client, String.to_integer(asset_id),
      0.0, 1.0, 0.0)

    # Zone server sends a CH_ACK or entity snapshot within one RTT (500 ms)
    assert_receive {:zone_entities, entities}, 500
    assert is_map(entities)

    ZoneConsole.ZoneClient.stop(client)
  end
end
```

Run with:

```sh
cd multiplayer-fabric-zone-console
ZONE_SERVER_URL=https://zone-700a.chibifire.com \
ZONE_CERT_PIN=... \
TEST_ASSET_ID=<id from cycle 2> \
mix test --only prod test/zone_console/instance_command_test.exs
```

## GREEN — pass condition

The test passes. `{:zone_entities, entities}` is received within 500 ms.
The zone server logs show `CMD_INSTANCE_ASSET` was received:

```sh
fly logs --app multiplayer-fabric-zones | grep "CMD_INSTANCE_ASSET"
```

## REFACTOR

If the send_instance + assert_receive pattern is used in more tests, extract a
`ZoneConsole.TestClient` helper that connects, sends one command, collects the
next entity snapshot, and disconnects.

## Fly.io checks

```sh
# Confirm zone machine is running
fly status --app multiplayer-fabric-zones

# Watch live logs during the test
fly logs --app multiplayer-fabric-zones

# Print zone cert fingerprint (needed for ZONE_CERT_PIN)
fly ssh console --app multiplayer-fabric-zones -C \
  "openssl x509 -in /etc/zone/server.crt -noout -fingerprint -sha256"
```
