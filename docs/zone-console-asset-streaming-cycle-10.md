# Cycle 10 — Multi-platform verification

**Status:** [ ] RED  
**Effort:** High  
**Back:** [index](zone-console-asset-streaming.md)  
**Depends on:** Cycle 9

## What you get

The full pipeline verified natively on macOS (ARM), Linux (x86), and
Windows (x64). Certificate pinning and picoquic transport confirmed on each
platform. AccessKit UI tree verified where a screen reader is active.

## Infrastructure — unchanged from Cycle 9

```
All platforms connect to the same stack:
  hub-700a.chibifire.com  → Cloudflare Tunnel → zone-backend:4000 (Docker, host)
  zone-700a.chibifire.com → DNS A record → host IP → UDP 443 → zone-server (Docker)
  versitygw               → localhost:7070 (S3, Docker)
```

The host machine exposes:
- TCP 443 — Cloudflare Tunnel origin (handled by cloudflared container)
- UDP 443 — zone server WebTransport (router NAT → Docker port 443)

## Platform matrix

| Platform        | zone_console build      | HTTP path                 | UDP path           | AccessKit        |
| --------------- | ----------------------- | ------------------------- | ------------------ | ---------------- |
| macOS ARM       | `mix escript.build`     | Cloudflare Tunnel / HTTPS | direct UDP 443     | NSAccessibility  |
| Linux x86       | `mix escript.build`     | Cloudflare Tunnel / HTTPS | direct UDP 443     | AT-SPI2          |
| Windows x64     | `mix escript.build`     | Cloudflare Tunnel / HTTPS | direct UDP 443     | UI Automation    |

## RED — failing tests

File: `test/zone_console/multi_platform_test.exs`

```elixir
defmodule ZoneConsole.MultiPlatformTest do
  use ExUnit.Case, async: false

  @platform case :os.type() do
    {:unix, :darwin}  -> :macos
    {:unix, :linux}   -> :linux
    {:win32, :nt}     -> :windows
  end

  @tag :prod
  test "zone_console connects and instances on #{@platform}" do
    url      = System.fetch_env!("ZONE_SERVER_URL")
    pin      = System.fetch_env!("ZONE_CERT_PIN")
    asset_id = String.to_integer(System.fetch_env!("TEST_ASSET_ID"))

    {:ok, zc} = ZoneConsole.ZoneClient.start_link(url, pin, 1, self())
    ZoneConsole.ZoneClient.send_instance(zc, asset_id, 0.0, 1.0, 0.0)

    assert_receive {:zone_entities, entities}, 2_000
    found = Enum.any?(Map.values(entities), fn e -> abs(e.cy - 1.0) < 0.5 end)
    assert found, "#{@platform}: entity near y=1.0 must appear"

    ZoneConsole.ZoneClient.stop(zc)
  end

  @tag :prod
  @tag :accesskit
  test "AccessKit tree shows instanced node on #{@platform}" do
    asset_id = System.fetch_env!("TEST_ASSET_ID")

    {:ok, ax_tree} = ZoneConsole.AccessKit.get_tree(@platform)
    node = Enum.find(ax_tree[:nodes] || [], fn n ->
      n[:label] == asset_id or n["label"] == asset_id
    end)
    assert node != nil, "#{@platform}: instanced node must appear in AccessKit tree"
    assert node[:accessible] == true or node["accessible"] == true
  end
end
```

Run on each platform (same env vars as Cycle 9, plus `TEST_ASSET_ID`):

```sh
# Transport test (all platforms)
mix test --only prod test/zone_console/multi_platform_test.exs

# AccessKit test (requires active screen reader)
mix test --only accesskit test/zone_console/multi_platform_test.exs
```

## GREEN — pass condition

Transport test passes on macOS ARM, Linux x86, and Windows x64.
AccessKit test passes with VoiceOver (macOS), Orca (Linux), Narrator (Windows).

## Verify Cloudflare Tunnel handles all three

```sh
# From each platform, confirm Cloudflare edge responds
curl -sI https://hub-700a.chibifire.com/health | grep -E "cf-ray|HTTP"

# Confirm latency from Cloudflare edge (target < 100 ms)
curl -sw "\nTotal: %{time_total}s\n" -o /dev/null \
  https://hub-700a.chibifire.com/health
```

## Verify UDP 443 reachable from each platform

```sh
# macOS / Linux
nc -u -w2 zone-700a.chibifire.com 443 && echo "UDP open"

# Windows (PowerShell)
$udp = New-Object System.Net.Sockets.UdpClient
$udp.Connect("zone-700a.chibifire.com", 443)
Write-Host "UDP OK"
```

## REFACTOR

If `ZoneConsole.AccessKit.get_tree/1` requires platform-specific native calls,
implement it as a behaviour with three modules dispatched at runtime:

```elixir
defmodule ZoneConsole.AccessKit do
  def get_tree(platform) do
    case platform do
      :macos   -> ZoneConsole.AccessKit.MacOS.get_tree()
      :linux   -> ZoneConsole.AccessKit.Linux.get_tree()
      :windows -> ZoneConsole.AccessKit.Windows.get_tree()
    end
  end
end
```

Each implementation calls the platform's native accessibility API via a
Port or NIF. Stub with `{:ok, %{nodes: []}}` until each platform is wired.
