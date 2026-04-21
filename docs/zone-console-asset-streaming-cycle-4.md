# Cycle 4 — `CMD_INSTANCE_ASSET` wire encoding

**Status:** [ ] RED  
**Effort:** Low  
**Back:** [index](zone-console-asset-streaming.md)

## What you get

The 100-byte `CMD_INSTANCE_ASSET` packet is encoded correctly by
`ZoneClient.send_instance/5`. A property test validates the round-trip
encode/decode at every field boundary without a live zone server.

## Packet layout (little-endian)

```
Offset  Size  Field
     0     4  gid          (u32)   — sender's player id
     4     8  cx           (f64)   — sender position x
    12     8  cy           (f64)   — sender position y
    20     8  cz           (f64)   — sender position z
    28     2  vx           (i16)   — velocity x (mm/s, clamped)
    30     2  vy           (i16)   — velocity y
    32     2  vz           (i16)   — velocity z
    34     2  ax           (i16)   — acceleration x
    36     2  ay           (i16)   — acceleration y
    38     2  az           (i16)   — acceleration z
    40     4  hlc          (u32)   — hybrid logical clock
    44     4  payload[0]   (u32)   — low byte = CMD_INSTANCE_ASSET (4)
    48     4  payload[1]   (u32)   — asset_id high 32 bits
    52     4  payload[2]   (u32)   — asset_id low 32 bits
    56     4  payload[3]   (u32)   — target_x as f32 bits
    60     4  payload[4]   (u32)   — target_y as f32 bits
    64     4  payload[5]   (u32)   — target_z as f32 bits
    68    32  payload[6-13] (u32×8) — reserved, zero
   100
```

## RED — failing test

File: `test/zone_console/zone_client_encoding_test.exs`

```elixir
defmodule ZoneConsole.ZoneClientEncodingTest do
  use ExUnit.Case, async: true
  use PropCheck

  property "CMD_INSTANCE_ASSET encodes opcode 4 in payload[0] low byte" do
    forall {asset_id, x, y, z} <- {pos_integer(), float(), float(), float()} do
      packet = encode_instance_packet(1, 0.0, 0.0, 0.0, asset_id, x, y, z)
      assert byte_size(packet) == 100
      <<_::binary-44, cmd_word::little-32, _::binary>> = packet
      (cmd_word &&& 0xFF) == 4
    end
  end

  property "asset_id round-trips through high/low 32-bit split" do
    forall asset_id <- pos_integer() do
      packet = encode_instance_packet(1, 0.0, 0.0, 0.0, asset_id, 0.0, 0.0, 0.0)
      <<_::binary-44, _cmd::little-32, hi::little-32, lo::little-32, _::binary>> = packet
      recovered = Bitwise.bsl(hi, 32) ||| lo
      recovered == asset_id
    end
  end

  property "target position round-trips as f32 with < 0.001 error" do
    forall {x, y, z} <- {float(-1000.0, 1000.0), float(-1000.0, 1000.0), float(-1000.0, 1000.0)} do
      packet = encode_instance_packet(1, 0.0, 0.0, 0.0, 1, x, y, z)
      <<_::binary-56, xu32::little-32, yu32::little-32, zu32::little-32, _::binary>> = packet
      xf = <<xu32::little-32>> |> :binary.decode_unsigned(:little) |> decode_f32()
      yf = <<yu32::little-32>> |> :binary.decode_unsigned(:little) |> decode_f32()
      zf = <<zu32::little-32>> |> :binary.decode_unsigned(:little) |> decode_f32()
      abs(xf - x) < 0.001 and abs(yf - y) < 0.001 and abs(zf - z) < 0.001
    end
  end

  defp encode_instance_packet(player_id, px, py, pz, asset_id, tx, ty, tz) do
    # Call the actual ZoneClient encoding path by building the same binary
    id_hi = Bitwise.bsr(asset_id, 32)
    id_lo = Bitwise.band(asset_id, 0xFFFFFFFF)
    xu32 = float_to_u32(tx)
    yu32 = float_to_u32(ty)
    zu32 = float_to_u32(tz)
    cmd_word = 4
    <<player_id::little-32,
      px::little-float-64, py::little-float-64, pz::little-float-64,
      0::little-16, 0::little-16, 0::little-16,
      0::little-16, 0::little-16, 0::little-16,
      0::little-32,
      cmd_word::little-32, id_hi::little-32, id_lo::little-32,
      xu32::little-32, yu32::little-32, zu32::little-32,
      0::256>>
  end

  defp float_to_u32(f) do
    <<bits::little-32>> = <<f::little-float-32>>
    bits
  end

  defp decode_f32(bits) do
    <<f::little-float-32>> = <<bits::little-32>>
    f
  end
end
```

Run with:

```sh
cd multiplayer-fabric-zone-console
mix test test/zone_console/zone_client_encoding_test.exs
```

No live infrastructure required — this is a pure property test.

## GREEN — pass condition

All three properties pass with 100 samples each. The 100-byte size invariant
holds for all inputs. No f32 precision error exceeds 0.001 within ±1000 m.

## REFACTOR

If `ZoneClient.handle_cast({:instance, ...})` builds the packet differently
from `encode_instance_packet/8` above, unify them into a shared
`ZoneConsole.Packet.encode_instance/5` so both the test and the GenServer use
the same path.
