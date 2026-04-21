# Cycle 7 — Zone server lifecycle (Docker `editor=no`)

**Status:** [ ] RED  
**Effort:** High  
**Back:** [index](zone-console-asset-streaming.md)  
**Depends on:** Cycle 5

## What you get

Uro manages the zone server container lifecycle. It can start, stop, and
query the running zone server. `zone_console` can retrieve the live zone
topology via `GET /zones`.

## Infrastructure

```
docker-compose.yml
  zone-server:
    image: multiplayer-fabric-godot-server:latest   # editor=no
    ports: ["443:443/udp"]
    environment:
      WEBTRANSPORT_HOST: zone-700a.chibifire.com
      WEBTRANSPORT_PORT: 443

zone-backend manages zone state in CockroachDB
  GET /zones → returns [{address, port, cert_hash}]
```

The zone server image is built with `editor=no` (no editor code in binary).
It starts automatically as part of `docker compose up -d`. For the purposes
of this cycle, one zone server running on the host is sufficient.

The Cloudflare DNS A record for `zone-700a.chibifire.com` points to the
host's public IP and must have the **orange cloud disabled** (DNS only).
Router UDP 443 → host is required.

## RED — failing tests

File: `test/zone_console/zone_lifecycle_test.exs`

```elixir
defmodule ZoneConsole.ZoneLifecycleTest do
  use ExUnit.Case, async: false

  defp authed_client do
    ZoneConsole.UroClient.new(System.fetch_env!("URO_BASE_URL"))
    |> then(fn c ->
      {:ok, a} = ZoneConsole.UroClient.login(c,
        System.fetch_env!("URO_EMAIL"),
        System.fetch_env!("URO_PASSWORD"))
      a
    end)
  end

  @tag :prod
  test "GET /zones returns at least one running zone" do
    {:ok, zones} = ZoneConsole.UroClient.list_zones(authed_client())
    assert length(zones) >= 1
  end

  @tag :prod
  test "each zone entry has address, port, and cert_hash" do
    {:ok, zones} = ZoneConsole.UroClient.list_zones(authed_client())

    Enum.each(zones, fn zone ->
      assert is_binary(zone["address"] || zone[:address]),
             "zone must have address"
      assert is_integer(zone["port"] || zone[:port]),
             "zone must have integer port"
      assert is_binary(zone["cert_hash"] || zone[:cert_hash]),
             "zone must have cert_hash"
    end)
  end
end
```

Run:

```sh
cd multiplayer-fabric-zone-console
URO_BASE_URL=https://hub-700a.chibifire.com \
URO_EMAIL=... URO_PASSWORD=... \
mix test --only prod test/zone_console/zone_lifecycle_test.exs
```

## GREEN — pass condition

Both tests pass. `GET /zones` returns a JSON array with the zone server's
address, port, and cert_hash.

Verify directly:

```sh
docker ps | grep zone-server

curl -s https://hub-700a.chibifire.com/zones \
  -H "Authorization: Bearer $TOKEN" | python3 -m json.tool
```

## Implementation steps

### 1. Build the zone server image

```sh
cd multiplayer-fabric-godot
docker build --target zone-server \
  -t multiplayer-fabric-godot-server:latest \
  -f Dockerfile .
```

### 2. Zone server prints cert hash on stdout at boot

The zone server writes its SHA-256 cert fingerprint to stdout:

```
CERT_HASH: aa:bb:cc:...
```

Zone-backend reads this from the container logs on startup via:

```elixir
{output, 0} = System.cmd("docker", ["logs", container_id])
cert_hash = Regex.run(~r/CERT_HASH: (.+)/, output, capture: :all_but_first)
```

### 3. Expose GET /zones

In `multiplayer-fabric-zone-backend`, add a controller that reads
zone state from a CockroachDB table (or ETS cache) and returns
`%{data: %{zones: [%{address:, port:, cert_hash:}]}}`.

## Cloudflare DNS note

```sh
# Confirm zone-700a.chibifire.com resolves to host machine IP, not CF
dig zone-700a.chibifire.com +short
# expect 173.180.240.105

# Confirm UDP 443 is reachable
nc -u -w2 zone-700a.chibifire.com 443 && echo "UDP open"
```
