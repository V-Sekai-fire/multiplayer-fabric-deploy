defmodule MultiplayerFabricDeploy.ZoneAssetStreamingIntegrationTest do
  @moduledoc """
  Integration tests for the full zone asset streaming pipeline (Cycles 6-8).

  This is UPSIDE-DOWN RED-GREEN-REFACTOR TDD: the test is written FIRST to
  define the contract, then implementation follows.

  Pipeline:
    1. upload: zone_console sends raw scene + deps to uro
    2. bake (ephemeral FLAME): uro spawns editor=yes baker, returns .godot/imported
    3. instance: zone_console issues CMD_INSTANCE_ASSET to zone server
    4. authority zone handler: authority zone's Godot process runs taskweft pipeline
       - fetch_manifest (get chunk list from uro)
       - download_chunks (casync pull all deps)
       - sha_verify (validate each chunk)
       - sandbox_load (RISC-V VM boundary; scripts run inside)
       - structural_verify (root node type sane, node count ≤ MAX, no res:// refs)
       - instantiate (add_child at pos, broadcast CH_INTEREST ghost)

  Pass conditions depend on the zone network topology being available (Cycles 7-8).
  This file defines the shape of what must be implemented.
  """

  # Zone network is stateful
  use ExUnit.Case, async: false
  @moduletag :integration

  alias MultiplayerFabricDeploy.ZoneAsset
  alias MultiplayerFabricDeploy.ZoneAsset.InstancePipeline
  alias MultiplayerFabricDeploy.ZoneAsset.AuthorityInvariant
  alias MultiplayerFabricDeploy.HilbertCurve

  setup do
    # These tests require a running zone network.
    # Precondition: docker compose up -d (CockroachDB + uro + zone-server)
    # Or: local FLAME-driven stack with Fly.io override.

    {:ok,
     zone_server_url: System.get_env("ZONE_SERVER_URL", "https://zone-700a.chibifire.com"),
     uro_manifest_url: System.get_env("URO_MANIFEST_URL", "https://uro.chibifire.com"),
     cert_pin: System.get_env("ZONE_CERT_PIN", "abc123...")}
  end

  # ============================================================================
  # CYCLE 6: Godot zone handler — authority zone instances the baked scene
  # ============================================================================

  describe "Cycle 6: CMD_INSTANCE_ASSET zone handler" do
    test "authority zone receives CMD_INSTANCE_ASSET and runs instance pipeline",
         %{zone_server_url: zone_url, cert_pin: pin} do
      asset_id = "550e8400-e29b-41d4-a716-446655440000"
      pos = {0.0, 1.0, 0.0}

      # GIVEN: an asset has been uploaded and baked
      # (Cycles 1-5 completed: manifest exists in uro)

      # WHEN: zone_console sends CMD_INSTANCE_ASSET to the zone server
      {:ok, response} =
        ZoneAsset.send_instance_command(
          zone_url,
          asset_id,
          pos,
          cert_pin: pin
        )

      # THEN: the command reaches the AUTHORITY zone (Hilbert routing)
      assert response.packet_type == :ack
      assert response.command_id == :cmd_instance_asset
      assert response.status == :accepted
    end

    test "authority zone fetches manifest from uro" do
      # GIVEN: uro has a valid manifest for the asset
      # WHEN: authority zone calls fetch_manifest in the pipeline
      {:ok, manifest} = InstancePipeline.fetch_manifest("asset-id", "https://uro.chibifire.com")

      # THEN: manifest contains chunk list
      assert manifest["chunks"] != nil
      assert is_list(manifest["chunks"])
      assert Enum.all?(manifest["chunks"], &is_binary/1)
    end

    test "authority zone downloads all chunks via casync" do
      # GIVEN: a valid manifest with chunks
      chunks = ["chunk-a", "chunk-b", "chunk-c"]
      manifest = %{"chunks" => chunks}

      # WHEN: authority zone calls download_chunks
      {:ok, _chunk_data} = InstancePipeline.download_chunks(manifest, "/tmp/scene-store")

      # THEN: all chunks are present and readable
      Enum.each(chunks, fn chunk_id ->
        path = Path.join("/tmp/scene-store", chunk_id)
        assert File.exists?(path), "Chunk #{chunk_id} should exist"
      end)
    end

    test "authority zone verifies SHA-512/256 per chunk" do
      # GIVEN: downloaded chunks
      chunks = %{"chunk-a" => "data-a", "chunk-b" => "data-b"}

      manifest = %{
        "chunks" => [
          %{"id" => "chunk-a", "sha512_256" => compute_sha("data-a")},
          %{"id" => "chunk-b", "sha512_256" => compute_sha("data-b")}
        ]
      }

      # WHEN: authority zone calls sha_verify
      {:ok, verified} = InstancePipeline.sha_verify(chunks, manifest)

      # THEN: all chunks pass verification
      assert verified == true
    end

    test "authority zone loads scene into Godot Sandbox (RISC-V VM boundary)" do
      # GIVEN: verified chunks assembled into scene path
      scene_path = "/tmp/scene-store/mire.tscn"

      # WHEN: authority zone calls sandbox_load
      # This executes ResourceLoader::load() inside RISC-V VM
      {:ok, scene_object} = InstancePipeline.sandbox_load(scene_path)

      # THEN: scene object is valid and sandboxed
      assert is_map(scene_object)
      # proves RISC-V boundary
      assert scene_object.source == :sandbox
      # scripts ran inside VM
      assert scene_object.scripted == true
    end

    test "authority zone verifies scene structure (root node type, node count, no external refs)" do
      # GIVEN: a loaded scene object
      scene = %{
        root_node_type: "Node3D",
        node_count: 42,
        has_external_refs: false
      }

      # WHEN: authority zone calls structural_verify
      {:ok, valid} = InstancePipeline.structural_verify(scene, max_nodes: 1000)

      # THEN: structure is valid
      assert valid == true
    end

    test "structural_verify rejects invalid root node type" do
      # GIVEN: a scene with forbidden root type
      scene = %{
        # Not allowed
        root_node_type: "GDScript",
        node_count: 10,
        has_external_refs: false
      }

      # WHEN: authority zone calls structural_verify
      {:error, reason} = InstancePipeline.structural_verify(scene, max_nodes: 1000)

      # THEN: verification fails
      assert reason == :invalid_root_node_type
    end

    test "structural_verify rejects too many nodes" do
      # GIVEN: a scene exceeding node limit
      scene = %{
        root_node_type: "Node3D",
        # Exceeds MAX_ASSET_NODES (10k)
        node_count: 10_001,
        has_external_refs: false
      }

      # WHEN: authority zone calls structural_verify
      {:error, reason} = InstancePipeline.structural_verify(scene, max_nodes: 10_000)

      # THEN: verification fails
      assert reason == :node_count_exceeded
    end

    test "structural_verify rejects scenes with external res:// refs" do
      # GIVEN: a scene with external resource references
      scene = %{
        root_node_type: "Node3D",
        node_count: 50,
        # Violates safety boundary
        has_external_refs: true
      }

      # WHEN: authority zone calls structural_verify
      {:error, reason} = InstancePipeline.structural_verify(scene, max_nodes: 1000)

      # THEN: verification fails
      assert reason == :external_refs_forbidden
    end

    test "authority zone instantiates scene at position" do
      # GIVEN: a verified scene object and target position
      scene = %{root_node_type: "Node3D", node_count: 42, has_external_refs: false}
      pos = {10.0, 5.0, -3.0}

      # WHEN: authority zone calls instantiate
      {:ok, instance_node} = InstancePipeline.instantiate(scene, pos)

      # THEN: node is added to scene tree at the correct position
      assert instance_node.position == pos
      assert instance_node.parent_node_id == :scene_root
      assert instance_node.state == :active
    end

    test "authority zone broadcasts CH_INTEREST ghost to neighbouring zones" do
      # GIVEN: instantiated scene at Hilbert position
      pos = {0.0, 1.0, 0.0}
      hilbert_cell = hilbert_3d(pos)

      # WHEN: authority zone broadcasts CH_INTEREST
      {:ok, broadcast_msg} = InstancePipeline.broadcast_interest_ghost(hilbert_cell, pos)

      # THEN: interest zones within AOI_CELLS receive the ghost
      assert broadcast_msg.message_type == :ch_interest
      assert broadcast_msg.entity_id != nil
      assert broadcast_msg.position == pos
      assert broadcast_msg.replica_type == :ghost
    end

    test "authority invariant: only authority zone executes CMD_INSTANCE_ASSET" do
      # GIVEN: a packet arriving at a non-authority zone
      pos = {10.0, 10.0, 10.0}
      authority_hilbert = hilbert_3d(pos)
      non_authority_hilbert = hilbert_3d({20.0, 20.0, 20.0})

      # WHEN: non-authority zone receives CMD_INSTANCE_ASSET for pos
      {:ok, handled?} =
        AuthorityInvariant.verify_authority(
          non_authority_hilbert,
          authority_hilbert,
          :cmd_instance_asset,
          pos
        )

      # THEN: it should NOT execute locally; it should forward to authority
      assert handled? == false
    end

    test "authority invariant: authority zone executes CMD_INSTANCE_ASSET" do
      # GIVEN: a packet arriving at the authority zone
      pos = {10.0, 10.0, 10.0}
      authority_hilbert = hilbert_3d(pos)

      # WHEN: authority zone receives CMD_INSTANCE_ASSET for pos
      {:ok, execute?} =
        AuthorityInvariant.verify_authority(
          authority_hilbert,
          authority_hilbert,
          :cmd_instance_asset,
          pos
        )

      # THEN: it should execute locally
      assert execute? == true
    end
  end

  # ============================================================================
  # CYCLE 7: Round-trip integration smoke test
  # ============================================================================

  describe "Cycle 7: Round-trip smoke test" do
    test "full pipeline: upload → bake → instance → entity list confirmation",
         %{zone_server_url: zone_url, uro_manifest_url: uro_url, cert_pin: pin} do
      # Scenario: zone_console user runs:
      #   join 0
      #   upload multiplayer-fabric-humanoid-project/humanoid/scenes/mire.tscn
      #   instance <returned-id> 0.0 1.0 0.0

      # Step 1: Upload raw scene
      scene_path =
        System.get_env(
          "TEST_SCENE_PATH",
          "multiplayer-fabric-humanoid-project/humanoid/scenes/mire.tscn"
        )

      {:ok, upload_response} = ZoneAsset.upload_scene(zone_url, scene_path, cert_pin: pin)
      asset_id = upload_response.asset_id
      assert is_binary(asset_id), "Upload should return asset_id"

      # Step 2: Verify manifest is in uro
      {:ok, manifest} = ZoneAsset.get_manifest(uro_url, asset_id)
      assert manifest["chunks"] != nil

      # Step 3: Send instance command to zone server
      pos = {0.0, 1.0, 0.0}

      {:ok, instance_response} =
        ZoneAsset.send_instance_command(zone_url, asset_id, pos, cert_pin: pin)

      assert instance_response.status == :accepted

      # Step 4: Poll zone entity list for the new entity
      {:ok, entity_list} = ZoneAsset.poll_entity_list(zone_url, cert_pin: pin)

      # Verify entity exists near the instantiation point
      entity = find_entity_near(entity_list, pos, tolerance: 0.1)
      assert entity != nil, "Entity should appear in zone list"
      assert entity.asset_id == asset_id

      # Step 5: Verify interest zones received CH_INTEREST ghost within one RTT
      neighbour_zones = get_neighbour_zone_urls(zone_url)

      Enum.each(neighbour_zones, fn neighbour_url ->
        {:ok, neighbour_list} = ZoneAsset.poll_entity_list(neighbour_url, cert_pin: pin)

        entity = find_entity_by_id(neighbour_list, asset_id)
        assert entity != nil, "Neighbour zone should receive ghost replica"
        assert entity.replica_type == :ghost
      end)
    end

    test "authority zone logs confirm correct zone handled the packet" do
      # GIVEN: instance command sent for a specific position
      pos = {5.0, 5.0, 5.0}
      authority_zone_id = zone_id_for_hilbert(hilbert_3d(pos))

      # WHEN: zone server logs are captured
      {:ok, logs} = ZoneAsset.fetch_zone_logs()

      # THEN: logs show authority zone (not a forwarding zone) handled CMD_INSTANCE_ASSET
      assert Enum.any?(logs, fn log ->
               String.contains?(log, [
                 "CMD_INSTANCE_ASSET",
                 "authority",
                 to_string(authority_zone_id)
               ])
             end)
    end
  end

  # ============================================================================
  # CYCLE 8: Native multi-platform smoke test
  # ============================================================================

  describe "Cycle 8: Native multi-platform smoke test" do
    @platforms [:linux, :macos, :windows]

    test "native WebTransport client (picoquic) connects on all platforms" do
      Enum.each(@platforms, fn platform ->
        zone_url = System.get_env("ZONE_SERVER_URL", "https://zone-700a.chibifire.com")

        {:ok, _client} =
          ZoneAsset.WebTransportClient.connect(zone_url, platform: platform, cert_pin: "...")

        # THEN: client is connected and ready
        assert is_map(_client)
        assert _client.platform == platform
      end)
    end

    test "entity appears in zone list on all native platforms" do
      scene_path =
        System.get_env(
          "TEST_SCENE_PATH",
          "multiplayer-fabric-humanoid-project/humanoid/scenes/mire.tscn"
        )

      pos = {0.0, 1.0, 0.0}

      Enum.each(@platforms, fn platform ->
        zone_url = System.get_env("ZONE_SERVER_URL", "https://zone-700a.chibifire.com")

        {:ok, client} = ZoneAsset.WebTransportClient.connect(zone_url, platform: platform)

        # Upload
        {:ok, upload_resp} = ZoneAsset.WebTransportClient.upload(client, scene_path)
        asset_id = upload_resp.asset_id

        # Instance
        {:ok, instance_resp} =
          ZoneAsset.WebTransportClient.send_instance_command(client, asset_id, pos)

        assert instance_resp.status == :accepted

        # Poll entity list
        {:ok, entity_list} = ZoneAsset.WebTransportClient.get_entity_list(client)

        entity = find_entity_near(entity_list, pos, tolerance: 0.1)
        assert entity != nil, "#{platform}: entity should appear"
        assert entity.asset_id == asset_id
      end)
    end

    test "AccessKit tree reflects instanced node on platforms with screen reader" do
      # macOS and Windows support AccessKit for native UI tree verification
      # (Linux uses Linux AT-SPI2, also supported)
      scene_path =
        System.get_env(
          "TEST_SCENE_PATH",
          "multiplayer-fabric-humanoid-project/humanoid/scenes/mire.tscn"
        )

      pos = {0.0, 1.0, 0.0}

      [:macos, :windows, :linux]
      |> Enum.each(fn platform ->
        zone_url = System.get_env("ZONE_SERVER_URL", "https://zone-700a.chibifire.com")

        {:ok, client} =
          ZoneAsset.WebTransportClient.connect(zone_url, platform: platform)

        {:ok, upload_resp} = ZoneAsset.WebTransportClient.upload(client, scene_path)
        asset_id = upload_resp.asset_id

        {:ok, _} = ZoneAsset.WebTransportClient.send_instance_command(client, asset_id, pos)

        # Verify AccessKit tree
        {:ok, ax_tree} = ZoneAsset.AccessKit.get_tree(platform)

        # Find the instanced node in the tree
        node = find_ax_node_by_label(ax_tree, asset_id)
        assert node != nil, "#{platform}: instanced node in AccessKit tree"
        assert node.position == pos or approx_equal(node.position, pos)
      end)
    end
  end

  # ============================================================================
  # Helpers
  # ============================================================================

  defp compute_sha(data) do
    :crypto.hash(:sha512_256, data)
    |> Base.encode16(case: :lower)
  end

  defp hilbert_3d({x, y, z}) do
    # Use proper 3D Hilbert curve implementation
    # Grid order = 256 (2^8), so coordinates are 0-255
    HilbertCurve.world_to_hilbert({x, y, z}, grid_size: 10000.0, grid_order: 256)
  end

  defp zone_id_for_hilbert(hilbert_code) do
    # Map Hilbert code to zone ID (assume 100 zones)
    HilbertCurve.hilbert_to_zone(hilbert_code, 100)
  end

  defp find_entity_near(entity_list, {tx, ty, tz}, tolerance: tol) do
    Enum.find(entity_list, fn entity ->
      {ex, ey, ez} = entity.position
      abs(ex - tx) <= tol and abs(ey - ty) <= tol and abs(ez - tz) <= tol
    end)
  end

  defp find_entity_by_id(entity_list, asset_id) do
    Enum.find(entity_list, &(&1.asset_id == asset_id))
  end

  defp get_neighbour_zone_urls(zone_url) do
    # Placeholder: return list of neighbour zone URLs based on AOI_CELLS
    []
  end

  defp find_ax_node_by_label(ax_tree, label) do
    # Traverse AccessKit tree to find node with matching label
    nodes = ax_tree[:nodes] || ax_tree["nodes"] || []

    Enum.find(nodes, fn node ->
      node[:label] == label or node["label"] == label
    end)
  end

  defp approx_equal({x1, y1, z1}, {x2, y2, z2}, tolerance \\ 0.001) do
    abs(x1 - x2) <= tolerance and
      abs(y1 - y2) <= tolerance and
      abs(z1 - z2) <= tolerance
  end
end
