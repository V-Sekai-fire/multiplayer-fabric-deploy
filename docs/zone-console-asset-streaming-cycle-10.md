# Cycle 10 — Multi-platform verification

**Status:** [ ] RED  
**Effort:** High  
**Back:** [index](zone-console-asset-streaming.md)  
**Depends on:** Cycle 9

## What you get

The full pipeline verified natively on macOS (ARM and x86), Linux (ARM and
x86), and Windows (x64). Certificate pinning, picoquic transport, and the
AccessKit UI tree are confirmed independently on each platform.

## Platform matrix

| Platform         | zone_console build | Zone transport | AccessKit backend |
| ---------------- | ------------------ | -------------- | ----------------- |
| macOS ARM        | `mix escript.build` | picoquic/QUIC  | NSAccessibility   |
| macOS x86        | `mix escript.build` | picoquic/QUIC  | NSAccessibility   |
| Linux x86 (Fly)  | `mix escript.build` | picoquic/QUIC  | AT-SPI2           |
| Windows x64      | `mix escript.build` | picoquic/QUIC  | UI Automation     |

## RED — failing tests

File: `test/zone_console/multi_platform_test.exs`

```elixir
defmodule ZoneConsole.MultiPlatformTest do
  use ExUnit.Case, async: false

  # Detect current platform
  @platform case :os.type() do
    {:unix, :darwin}  -> :macos
    {:unix, :linux}   -> :linux
    {:win32, :nt}     -> :windows
  end

  @tag :prod
  test "zone_console connects and instances on #{@platform}" do
    url = System.fetch_env!("ZONE_SERVER_URL")
    pin = System.fetch_env!("ZONE_CERT_PIN")

    {:ok, zc} = ZoneConsole.ZoneClient.start_link(url, pin, 1, self())

    asset_id = String.to_integer(System.fetch_env!("TEST_ASSET_ID"))
    ZoneConsole.ZoneClient.send_instance(zc, asset_id, 0.0, 1.0, 0.0)

    assert_receive {:zone_entities, entities}, 2_000
    found = Enum.any?(Map.values(entities), fn e -> abs(e.cy - 1.0) < 0.5 end)
    assert found, "#{@platform}: entity near y=1.0 must appear"

    ZoneConsole.ZoneClient.stop(zc)
  end

  @tag :prod
  @tag :accesskit
  test "AccessKit tree shows instanced node on #{@platform}" do
    # Run AFTER the instance command above so the entity is already in the world.
    asset_id = System.fetch_env!("TEST_ASSET_ID")

    {:ok, ax_tree} = ZoneConsole.AccessKit.get_tree(@platform)
    node = find_node_by_label(ax_tree, asset_id)
    assert node != nil, "#{@platform}: AccessKit tree must contain instanced node"
    assert node[:accessible] == true
  end

  defp find_node_by_label(tree, label) do
    nodes = tree[:nodes] || tree["nodes"] || []
    Enum.find(nodes, fn n -> n[:label] == label or n["label"] == label end)
  end
end
```

Run on each target platform:

```sh
cd multiplayer-fabric-zone-console
ZONE_SERVER_URL=https://zone-700a.chibifire.com \
ZONE_CERT_PIN=... TEST_ASSET_ID=<id> \
mix test --only prod test/zone_console/multi_platform_test.exs
```

Run the AccessKit subset separately (requires screen reader active):

```sh
mix test --only accesskit test/zone_console/multi_platform_test.exs
```

## GREEN — pass condition

The transport test passes on all four platform/arch combinations. The
AccessKit test passes on macOS (VoiceOver on), Linux (Orca + AT-SPI2), and
Windows (Narrator on).

## REFACTOR

If `ZoneConsole.AccessKit.get_tree/1` requires platform-specific native code,
wrap it behind a behaviour with three implementations
(`AccessKit.MacOS`, `AccessKit.Linux`, `AccessKit.Windows`) dispatched via
compile-time `@platform` or runtime `:os.type/0`.

## Fly.io build matrix

```sh
# Build zone_console escript for Linux inside a Fly ephemeral machine
fly machine run --app multiplayer-fabric-uro \
  --image hexpm/elixir:1.17.3-erlang-27.0.1-debian-bookworm-20240904-slim \
  --command "cd /app && mix escript.build" \
  --volume zone_console_src:/app
```

Windows and macOS builds are produced locally then published to the GitHub
release via `fly storage cp` to Tigris:

```sh
# macOS ARM
MIX_TARGET=macos-arm mix escript.build
fly storage cp zone_console \
  tigris://uro-uploads/releases/zone_console-macos-arm

# Windows (cross-compile from macOS via Wine or CI)
```

## Cloudflare edge validation

After all platform tests pass, run a final latency check from each geography
using Cloudflare Workers:

```sh
curl "https://uro.chibifire.com/healthz" \
  -H "CF-IPCountry: CA" -sw "\nLatency: %{time_total}s\n" -o /dev/null
```

Target: < 100 ms from Toronto. Cloudflare's `yyz` PoP should hit the
`multiplayer-fabric-uro` Fly machine in `yyz` with < 5 ms internal latency.
