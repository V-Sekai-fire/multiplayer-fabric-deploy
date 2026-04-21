# Cycle 8 — Native Multi-Platform smoke test

**Status:** [ ] not started  
**Effort:** High  
**Depends on:** Cycles 6 and 7  
**Back:** [index](zone-console-asset-streaming.md)

## What you get

A manual integration test using native clients across Linux, macOS, and Windows. This verifies that the picoquic backend correctly handles the Full Asset Ingestion pipeline with shared certificate pinning logic across all OS variants.

## Preconditions

- Full Fly.io/FLAME stack running (or local Docker equivalent).
- Native builds for target platforms (Linux ARM/x86, macOS ARM/x86, Windows x64).
- `zone_console` running natively on macOS.

## Native WebTransport client

The client connects to the zone server via native WebTransport (picoquic).
This bypasses all browser limitations and ensures bit-for-bit parity with
the server's internal protocol across macOS, Windows, and Linux.

## Pass condition

The authority zone entity list shows the instanced node on all platforms. Additionally, on native platforms with a screen reader active, the AccessKit tree reflects the instanced mire node accurately.
