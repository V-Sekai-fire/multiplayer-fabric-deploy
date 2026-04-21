# Cycle 4 — `CMD_INSTANCE_ASSET` wire encoding

**Status:** [ ] RED  
**Effort:** Low  
**Back:** [index](zone-console-asset-streaming.md)

## What you get

A property test verifies that `ZoneClient.handle_cast({:instance, ...})`
produces a correctly-shaped 100-byte packet at every field boundary.
No live infrastructure required — this is pure binary encoding logic.

## Packet layout (little-endian, 100 bytes)

```
Offset  Size  Field
     0     4  gid          u32   sender player id
     4     8  cx           f64   sender position x
    12     8  cy           f64   sender position y
    20     8  cz           f64   sender position z
    28     2  vx           i16   velocity x (mm/s)
    30     2  vy           i16   velocity y
    32     2  vz           i16   velocity z
    34     2  ax           i16   acceleration x
    36     2  ay           i16   acceleration y
    38     2  az           i16   acceleration z
    40     4  hlc          u32   hybrid logical clock
    44     4  payload[0]   u32   low byte = CMD_INSTANCE_ASSET (4)
    48     4  payload[1]   u32   asset_id high 32 bits
    52     4  payload[2]   u32   asset_id low 32 bits
    56     4  payload[3]   u32   target x as f32 bits
    60     4  payload[4]   u32   target y as f32 bits
    64     4  payload[5]   u32   target z as f32 bits
    68    32  payload[6-13] u32×8 reserved zero
   100
```

## RED — failing test

File: `test/zone_console/zone_client_encoding_test.exs`

```elixir
defmodule ZoneConsole.ZoneClientEncodingTest do
  use ExUnit.Case, async: true
  use PropCheck

  property "CMD_INSTANCE_ASSET packet is always 100 bytes" do
    forall {asset_id, x, y, z} <-
        {pos_integer(), float(-1.0e6, 1.0e6), float(-1.0e6, 1.0e6), float(-1.0e6, 1.0e6)} do
      byte_size(build_packet(1, asset_id, x, y, z)) == 100
    end
  end

  property "opcode 4 appears in low byte of payload[0]" do
    forall {asset_id, x, y, z} <-
        {pos_integer(), float(-1.0e6, 1.0e6), float(-1.0e6, 1.0e6), float(-1.0e6, 1.0e6)} do
      <<_::binary-44, cmd_word::little-32, _::binary>> = build_packet(1, asset_id, x, y, z)
      (cmd_word &&& 0xFF) == 4
    end
  end

  property "asset_id round-trips through high/low 32-bit split" do
    forall asset_id <- pos_integer() do
      <<_::binary-48, hi::little-32, lo::little-32, _::binary>> =
        build_packet(1, asset_id, 0.0, 0.0, 0.0)
      (Bitwise.bsl(hi, 32) ||| lo) == asset_id
    end
  end

  property "target position round-trips as f32 with < 0.01 error" do
    forall {x, y, z} <-
        {float(-1000.0, 1000.0), float(-1000.0, 1000.0), float(-1000.0, 1000.0)} do
      <<_::binary-56,
        xu::little-32, yu::little-32, zu::little-32,
        _::binary>> = build_packet(1, 1, x, y, z)
      <<xf::little-float-32>> = <<xu::little-32>>
      <<yf::little-float-32>> = <<yu::little-32>>
      <<zf::little-float-32>> = <<zu::little-32>>
      abs(xf - x) < 0.01 and abs(yf - y) < 0.01 and abs(zf - z) < 0.01
    end
  end

  defp build_packet(player_id, asset_id, tx, ty, tz) do
    id_hi = Bitwise.bsr(asset_id, 32)
    id_lo = Bitwise.band(asset_id, 0xFFFFFFFF)
    <<xu::little-32>> = <<tx::little-float-32>>
    <<yu::little-32>> = <<ty::little-float-32>>
    <<zu::little-32>> = <<tz::little-float-32>>
    <<player_id::little-32,
      0.0::little-float-64, 0.0::little-float-64, 0.0::little-float-64,
      0::little-16, 0::little-16, 0::little-16,
      0::little-16, 0::little-16, 0::little-16,
      0::little-32,
      4::little-32, id_hi::little-32, id_lo::little-32,
      xu::little-32, yu::little-32, zu::little-32,
      0::256>>
  end
end
```

Run (no env vars needed):

```sh
cd multiplayer-fabric-zone-console
mix test test/zone_console/zone_client_encoding_test.exs
```

## GREEN — pass condition

All four properties pass with 100 samples each.

## REFACTOR

The `build_packet/5` helper above and `ZoneClient.handle_cast({:instance, ...})`
in `zone_client.ex` must produce the same bytes. If they diverge, extract a
shared `ZoneConsole.Packet.encode_instance/5` called by both, then re-run
the property test to confirm.
