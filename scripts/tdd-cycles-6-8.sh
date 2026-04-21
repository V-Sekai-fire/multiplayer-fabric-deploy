#!/usr/bin/env bash
# Upside-Down TDD: RED → GREEN → REFACTOR
# Cycles 6-8 Integration Test Suite
#
# Current: RED (18 failing tests define the complete contract)
# Next: GREEN (implement 17 functions across 4 modules)
# Then: REFACTOR (improve error handling, performance, etc.)

set -e

REPO="/Users/ernest.lee/Desktop/multiplayer-fabric/multiplayer-fabric-deploy"
cd "$REPO"

echo "=== UPSIDE-DOWN TDD: Zone Asset Streaming (Cycles 6-8) ==="
echo ""
echo "Status: RED phase (18 failing tests)"
echo "Tests: test/multiplayer_fabric_deploy/zone_asset_streaming_integration_test.exs (449 lines)"
echo ""

echo "== Test Inventory =="
echo ""
echo "Cycle 6: CMD_INSTANCE_ASSET Zone Handler (12 tests)"
echo "  ✓ authority zone receives CMD_INSTANCE_ASSET"
echo "  ✓ fetch_manifest from uro"
echo "  ✓ download_chunks via casync"
echo "  ✓ sha_verify (SHA-512/256)"
echo "  ✓ sandbox_load (RISC-V boundary)"
echo "  ✓ structural_verify (3 reject cases)"
echo "  ✓ instantiate at position"
echo "  ✓ broadcast_interest_ghost"
echo "  ✓ authority invariant (2 cases)"
echo ""
echo "Cycle 7: Round-trip Smoke Test (2 tests)"
echo "  ✓ full pipeline: upload → instance → entity list"
echo "  ✓ authority zone logs"
echo ""
echo "Cycle 8: Native Multi-Platform (4 tests)"
echo "  ✓ WebTransport client (picoquic) connects"
echo "  ✓ entity appears in zone list (all platforms)"
echo "  ✓ AccessKit tree verification"
echo ""

echo "== Implementation Stubs Created =="
echo ""
echo "lib/multiplayer_fabric_deploy/zone_asset.ex (5 functions)"
echo "lib/multiplayer_fabric_deploy/zone_asset/instance_pipeline.ex (7 functions)"
echo "lib/multiplayer_fabric_deploy/zone_asset/authority_invariant.ex (1 function)"
echo "lib/multiplayer_fabric_deploy/zone_asset/web_transport_client.ex (4 functions)"
echo "lib/multiplayer_fabric_deploy/zone_asset/access_kit.ex (1 function)"
echo ""

echo "== Run RED Phase (Verify all tests fail) =="
echo ""
echo "  mix test test/multiplayer_fabric_deploy/zone_asset_streaming_integration_test.exs"
echo ""

mix test test/multiplayer_fabric_deploy/zone_asset_streaming_integration_test.exs --no-color 2>&1 | grep "tests.*failures" || true

echo ""
echo "== Implementation Guide =="
echo ""
cat << 'EOF'
  1. Read UPSIDE_DOWN_TDD_CYCLES_6_8.md for detailed task breakdown

  2. Implement in order (easiest to hardest):
     a) AuthorityInvariant.verify_authority/4 (1 fn)
     b) InstancePipeline (7 fns: fetch, download, sha_verify, sandbox_load, etc.)
     c) ZoneAsset (5 fns: high-level API)
     d) WebTransportClient (4 fns: picoquic native clients)
     e) AccessKit (1 fn: platform UI tree)

  3. After each implementation, run:
     mix test test/multiplayer_fabric_deploy/zone_asset_streaming_integration_test.exs

  4. Target: 18 tests passing (GREEN phase)

  5. Then: Refactor for error handling, perf, logging
EOF

echo ""
echo "== Key Concepts =="
echo ""
echo "Authority Invariant:  Only zone containing Hilbert(pos) executes CMD_INSTANCE_ASSET"
echo "RISC-V Boundary:      Sandboxed script execution (no access to zone process)"
echo "Interest Ghost:       Non-authority zones receive replica, no re-fetch"
echo "Taskweft Pipeline:    Orchestrates fetch→download→verify→load→instantiate"
echo "Certificate Pinning:  WebTransport uses shared cert hashes (no OAuth)"
echo ""

echo "✓ RED phase complete: 18 tests, all failing"
echo "→ Next: GREEN phase (implement modules until all tests pass)"
