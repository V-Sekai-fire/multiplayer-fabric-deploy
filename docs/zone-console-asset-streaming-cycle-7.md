# Cycle 7 — Round-trip integration smoke test

**Status:** [ ] not started  
**Effort:** High  
**Depends on:** Cycle 6  
**Back:** [index](zone-console-asset-streaming.md)

## What you get

A manual CLI smoke test that exercises the full pipeline end-to-end:
upload → instance → zone entity list confirmation.

## Preconditions

CockroachDB + VersityGW + uro + zone server all running.  On macOS this means Docker:

```sh
cd multiplayer-fabric-hosting && docker compose up -d
```

## Steps

From `zone_console` (runs natively on macOS):

```
join 0
upload multiplayer-fabric-humanoid-project/humanoid/scenes/mire.tscn
instance <returned-id> 0.0 1.0 0.0
```

## Authority check

The `instance` command sends `CMD_INSTANCE_ASSET` to the zone server.  The
server routes it to the authority zone for Hilbert code `hilbert3D(0, 1, 0)`.
Confirm in zone server logs that the correct zone handled the packet — not a
non-authority forwarding zone.

## Pass condition

The zone entity list shows a new entry near `(0.0, 1.0, 0.0)`.  Interest zones
within `AOI_CELLS` show a ghost replica of the same entity within one RTT of
the authority zone instancing it.
