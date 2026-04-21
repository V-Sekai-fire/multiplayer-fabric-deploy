# Cycle 5 — `instance` console command

**Status:** [ ] RED  
**Effort:** Low  
**Back:** [index](zone-console-asset-streaming.md)  
**Depends on:** Cycles 1, 2, 4

## What you get

Running `instance <id> <x> <y> <z>` in `zone_console` sends a
`CMD_INSTANCE_ASSET` packet to the live zone server and receives an entity
snapshot back. First cycle requiring a running zone server.

## Infrastructure path

```
zone_console (macOS)
  → ZoneClient.send_instance/5
  → native WebTransport / picoquic
  → UDP 443 → router NAT
  → zone-server:443/udp (Docker, host machine)
  → entity snapshot returned
```

Zone server traffic is **not** proxied by Cloudflare. The client connects
directly to `zone-700a.chibifire.com:443` using UDP (QUIC). The connection
is secured by the zone server's self-signed certificate, pinned via
`ZONE_CERT_PIN` (SHA-256 fingerprint of the cert).

Obtain the cert fingerprint after the zone-server container starts:

```sh
docker exec multiplayer-fabric-hosting-zone-server-1 \
  sh -c "openssl x509 -in /zone/certs/server.crt -noout -fingerprint -sha256 2>/dev/null \
    || cat /zone/certs/cert_hash.txt"
```

## RED — failing test

File: `test/zone_console/instance_command_test.exs`

```elixir
defmodule ZoneConsole.InstanceCommandTest do
  use ExUnit.Case, async: false

  @tag :prod
  test "instance command reaches zone server and gets entity snapshot" do
    url      = System.fetch_env!("ZONE_SERVER_URL")
    cert_pin = System.fetch_env!("ZONE_CERT_PIN")
    asset_id = System.fetch_env!("TEST_ASSET_ID")

    player_id = :rand.uniform(0x7FFFFFFF)
    {:ok, zc} = ZoneConsole.ZoneClient.start_link(url, cert_pin, player_id, self())

    ZoneConsole.ZoneClient.send_instance(zc,
      String.to_integer(asset_id), 0.0, 1.0, 0.0)

    assert_receive {:zone_entities, entities}, 500
    assert is_map(entities)

    ZoneConsole.ZoneClient.stop(zc)
  end
end
```

Run:

```sh
cd multiplayer-fabric-zone-console
ZONE_SERVER_URL=https://zone-700a.chibifire.com \
ZONE_CERT_PIN=<fingerprint> \
TEST_ASSET_ID=<id from Cycle 2> \
mix test --only prod test/zone_console/instance_command_test.exs
```

## GREEN — pass condition

Test passes and `{:zone_entities, entities}` is received within 500 ms.

Confirm the packet arrived at the zone server:

```sh
docker logs multiplayer-fabric-hosting-zone-server-1 2>&1 | \
  grep "CMD_INSTANCE_ASSET"
```

## REFACTOR

Extract a `ZoneConsole.TestHelpers.with_zone_client/3` helper that starts
a ZoneClient, runs a function, stops the client, and returns the result.
Reuse it in Cycle 9's round-trip test.

## Cloudflare DNS note

`zone-700a.chibifire.com` is an A record pointing to the host machine's
public IP (`173.180.240.105`). Cloudflare must have the proxy toggle
**disabled** (DNS only, grey cloud) for this record — proxying would
intercept QUIC traffic. Confirm:

```sh
dig zone-700a.chibifire.com +short
# must resolve to the host machine public IP, not Cloudflare's IPs
```

Router must forward UDP 443 to the host machine. Confirm from outside:

```sh
nc -u zone-700a.chibifire.com 443
```
