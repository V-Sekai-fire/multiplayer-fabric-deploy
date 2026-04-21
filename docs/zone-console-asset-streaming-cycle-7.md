# Cycle 7 — FLAME zone orchestrator

**Status:** [ ] RED  
**Effort:** High  
**Back:** [index](zone-console-asset-streaming.md)  
**Depends on:** Cycle 5

## What you get

Uro spawns, monitors, and replaces zone server machines on Fly.io using FLAME.
When a zone machine fails the BEAM supervisor automatically re-plans and
re-spawns, keeping the Hilbert grid covered. The zone console can query the
live machine inventory.

## Architecture

```
Uro.ZoneOrchestrator (FLAME parent)
  ├─ FLAME.Pool(Uro.ZonePool) — editor=no, perf-1x, 4 GB, auto-stop
  │    └─ zone machine(s): UDP 443, certificate printed on stdout at boot
  └─ ETS :zones — hilbert_range → {machine_id, cert_hash, started_at}
```

Uro exposes `GET /zones` to let `zone_console` read the live topology.

## RED — failing tests

File: `test/zone_console/zone_orchestrator_test.exs`

```elixir
defmodule ZoneConsole.ZoneOrchestratorTest do
  use ExUnit.Case, async: false

  @tag :prod
  test "GET /zones returns at least one running zone" do
    client =
      ZoneConsole.UroClient.new(System.fetch_env!("URO_BASE_URL"))
      |> then(fn c ->
        {:ok, a} = ZoneConsole.UroClient.login(c,
          System.fetch_env!("URO_EMAIL"), System.fetch_env!("URO_PASSWORD"))
        a
      end)

    {:ok, zones} = ZoneConsole.UroClient.list_zones(client)
    assert length(zones) >= 1
  end

  @tag :prod
  test "each zone entry has address, port, and cert_hash" do
    client =
      ZoneConsole.UroClient.new(System.fetch_env!("URO_BASE_URL"))
      |> then(fn c ->
        {:ok, a} = ZoneConsole.UroClient.login(c,
          System.fetch_env!("URO_EMAIL"), System.fetch_env!("URO_PASSWORD"))
        a
      end)

    {:ok, zones} = ZoneConsole.UroClient.list_zones(client)

    Enum.each(zones, fn zone ->
      assert is_binary(zone["address"] || zone[:address])
      assert is_integer(zone["port"]   || zone[:port])
      assert is_binary(zone["cert_hash"] || zone[:cert_hash])
    end)
  end
end
```

Run with:

```sh
cd multiplayer-fabric-zone-console
URO_BASE_URL=https://uro.chibifire.com URO_EMAIL=... URO_PASSWORD=... \
mix test --only prod test/zone_console/zone_orchestrator_test.exs
```

## GREEN — pass condition

Both tests pass. `GET /zones` returns a JSON array with at least one entry.
Each entry has `address`, `port`, and `cert_hash`.

Verify directly:

```sh
fly machines list --app multiplayer-fabric-zones
curl -s https://uro.chibifire.com/zones \
  -H "Authorization: Bearer $TOKEN" | jq .
```

## REFACTOR

If `list_zones/1` in `UroClient` currently expects `data.zones`, confirm the
uro controller returns `%{data: %{zones: [...]}}`. If the shape differs,
update the pattern match — one place, not scattered across tests.

## Fly.io deployment steps

### 1. Add ZonePool to uro application.ex

```elixir
{FLAME.Pool,
  name: Uro.ZonePool,
  backend: {FLAME.FlyBackend,
    image: "registry.fly.io/multiplayer-fabric-zones:latest",
    env: %{"GODOT_HEADLESS" => "1"},
    services: [%{internal_port: 7777, protocol: "udp",
                 ports: [%{port: 7777}]}]
  },
  min: 1, max: 20,
  cpu_kind: "performance-1x", memory_mb: 4096,
  idle_shutdown_after: :infinity}
```

### 2. Capture cert_hash on zone boot

On startup the zone server prints its certificate fingerprint to stdout.
A FLAME wrapper in uro reads this line and inserts it into ETS `:zones`.

### 3. Expose /zones endpoint

In `multiplayer-fabric-zone-backend`, `GET /zones` reads ETS `:zones` and
returns `{data: {zones: [...]}}`.

### 4. Deploy

```sh
fly deploy --app multiplayer-fabric-uro
fly machines list --app multiplayer-fabric-zones  # confirm new runner appeared
```

## Cloudflare check

`GET /zones` returns real-time machine state — it must not be cached.

```sh
curl -sI https://uro.chibifire.com/zones \
  -H "Authorization: Bearer $TOKEN" | grep cf-cache-status
# expect MISS or DYNAMIC
```

If CF returns HIT, add a Cache Rule: match `URI Path equals /zones`,
Cache Status = Bypass.
