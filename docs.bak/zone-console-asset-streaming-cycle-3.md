# Cycle 3 — CMD_INSTANCE_ASSET wire protocol

**Status:** [x] done  
**Effort:** Low  
**Back:** [index](zone-console-asset-streaming.md)

## What you get

The 100-byte `CMD_INSTANCE_ASSET` packet encoding is defined and the
Elixir console client can send it to the zone server over WebTransport.

## Implementation

`multiplayer-fabric-zone-console/lib/zone_console/zone_client.ex`.

- `send_instance/5` public API
- `handle_cast({:instance, asset_id, x, y, z})` encodes the packet:
  - Opcode: 4
  - `asset_id` split into two u32 payload slots (high word / low word)
  - Position: three f32 slots (`x`, `y`, `z`)
  - Total: 100 bytes (matches the zone server's fixed-size packet reader)

## Authority routing

The packet is sent to the zone server the console is currently joined to.
That server is responsible for routing `CMD_INSTANCE_ASSET` to the authority
zone for the target position — the zone whose Hilbert range contains
`hilbert3D(x, y, z)`.

## Pass condition

`ZoneClient.send_instance/5` completes without error; Wireshark/tcpdump
shows a 100-byte UDP datagram on port 443.
