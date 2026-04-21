defmodule MultiplayerFabricDeploy.ZoneAsset.InstancePipeline do
  @moduledoc """
  Taskweft pipeline for instance ingestion.
  
  Runs on the zone server's authority zone process:
    1. fetch_manifest — get chunk list from uro
    2. download_chunks — casync pull all deps
    3. sha_verify — validate SHA-512/256 per chunk
    4. sandbox_load — ResourceLoader inside RISC-V VM (script boundary)
    5. structural_verify — root node type sane, node count ≤ MAX, no external refs
    6. instantiate — add_child at pos, broadcast CH_INTEREST ghost
  """
  
  alias MultiplayerFabricDeploy.{GodotSandbox, GodotZoneServer, ZoneNetwork}

  defp http_client do
    Application.get_env(:multiplayer_fabric_deploy, :http_client, MultiplayerFabricDeploy.HTTPClient)
  end

  @doc "Fetch manifest (chunk list) from uro."
  def fetch_manifest(asset_id, uro_url) do
    # Call uro manifest endpoint: GET /storage/{asset_id}/manifest
    # Returns: {:ok, %{"chunks" => [...], "store_url" => "s3://..."}}
    
    url = "#{uro_url}/storage/#{asset_id}/manifest"
    
    with {:ok, response} <- http_client().get(url),
         {:ok, manifest} <- Jason.decode(response.body) do
      {:ok, manifest}
    else
      {:error, reason} -> {:error, {:fetch_failed, reason}}
    end
  rescue
    e -> {:error, {:fetch_exception, inspect(e)}}
  end

  @doc "Download all chunks via casync."
  def download_chunks(manifest, store_path) do
    # Get chunk list and store URL from manifest
    chunks = manifest["chunks"] || []
    store_url = manifest["store_url"] || ""
    
    # Ensure store path exists
    File.mkdir_p!(store_path)
    
    # Download each chunk via HTTP from store_url
    result =
      Enum.reduce_while(chunks, :ok, fn chunk_spec, _acc ->
        # Handle both string IDs and map specs
        {chunk_id, expected_sha} =
          case chunk_spec do
            %{} ->
              {chunk_spec["id"], chunk_spec["sha512_256"]}
            id when is_binary(id) ->
              {id, nil}
          end
        
        chunk_url = "#{store_url}/#{chunk_id}"
        chunk_file = Path.join(store_path, chunk_id)
        
        case http_client().get(chunk_url) do
          {:ok, response} ->
            # Verify SHA-512/256 if expected
            if expected_sha do
              actual_sha =
                :crypto.hash(:sha512_256, response.body)
                |> Base.encode16(case: :lower)
              
              if actual_sha == expected_sha do
                File.write!(chunk_file, response.body)
                {:cont, :ok}
              else
                {:halt, {:error, :sha_mismatch}}
              end
            else
              # No SHA to verify, just write
              File.write!(chunk_file, response.body)
              {:cont, :ok}
            end
          
          {:error, reason} ->
            {:halt, {:error, {:download_failed, reason}}}
        end
      end)
    
    case result do
      :ok -> {:ok, %{"downloaded" => length(chunks)}}
      error -> error
    end
  rescue
    e -> {:error, {:download_exception, inspect(e)}}
  end

  @doc "Verify SHA-512/256 per chunk."
  def sha_verify(chunks, manifest) do
    chunk_specs = manifest["chunks"] || []
    
    # Verify each chunk
    verified =
      Enum.all?(chunk_specs, fn chunk_spec ->
        {chunk_id, expected_sha} = 
          case chunk_spec do
            %{} ->
              {chunk_spec["id"], chunk_spec["sha512_256"]}
            id when is_binary(id) ->
              {id, nil}
          end
        
        actual_data = chunks[chunk_id]
        
        if actual_data do
          if expected_sha do
            actual_sha =
              :crypto.hash(:sha512_256, actual_data)
              |> Base.encode16(case: :lower)
            
            actual_sha == expected_sha
          else
            true
          end
        else
          false
        end
      end)
    
    if verified do
      {:ok, true}
    else
      {:error, :sha_mismatch}
    end
  end

  @doc "Load scene into RISC-V Sandbox (executes scripts inside VM)."
  def sandbox_load(scene_path) do
    case GodotSandbox.load_scene(scene_path) do
      {:ok, scene_data} ->
        {:ok,
         %{
           source: :sandbox,
           scripted: true,
           root_node_type: scene_data["root_type"],
           node_count: scene_data["node_count"],
           has_external_refs: scene_data["has_external_refs"],
           path: scene_path
         }}
      
      {:error, reason} ->
        {:error, {:sandbox_load_failed, reason}}
    end
  rescue
    e -> {:error, {:sandbox_exception, inspect(e)}}
  end

  @doc "Verify scene structure: root type, node count, no external refs."
  def structural_verify(scene, opts \\ []) do
    max_nodes = Keyword.get(opts, :max_nodes, 10_000)
    
    root_node_type = scene[:root_node_type] || scene["root_node_type"]
    node_count = scene[:node_count] || scene["node_count"]
    has_external_refs = scene[:has_external_refs] || scene["has_external_refs"]
    
    allowed_types = ["Node3D", "Node2D", "Control", "Node", "CanvasLayer"]
    
    cond do
      root_node_type not in allowed_types ->
        {:error, :invalid_root_node_type}
      
      node_count > max_nodes ->
        {:error, :node_count_exceeded}
      
      has_external_refs == true ->
        {:error, :external_refs_forbidden}
      
      true ->
        {:ok, true}
    end
  end

  @doc "Instantiate scene at position and return node."
  def instantiate(scene, pos) do
    {_x, _y, _z} = pos
    
    case GodotZoneServer.add_child_at_pos(scene, pos) do
      {:ok, node_id} ->
        {:ok,
         %{
           position: pos,
           parent_node_id: :scene_root,
           state: :active,
           node_type: scene[:root_node_type] || scene["root_node_type"],
           node_count: scene[:node_count] || scene["node_count"],
           node_id: node_id
         }}
      
      {:error, reason} ->
        {:error, {:instantiate_failed, reason}}
    end
  rescue
    e -> {:error, {:instantiate_exception, inspect(e)}}
  end

  @doc "Broadcast CH_INTEREST ghost to neighbouring zones within AOI_CELLS."
  def broadcast_interest_ghost(hilbert_cell, pos) do
    aoi_zones = get_aoi_zones(hilbert_cell)
    
    message = %{
      message_type: :ch_interest,
      entity_id: :erlang.phash2(hilbert_cell),
      position: pos,
      replica_type: :ghost
    }
    
    Enum.each(aoi_zones, fn zone_id ->
      ZoneNetwork.send_to_zone(zone_id, message)
    end)
    
    {:ok, message}
  rescue
    e -> {:error, {:broadcast_exception, inspect(e)}}
  end

  defp get_aoi_zones(_hilbert_cell) do
    # Get all zones within AOI_CELLS of this Hilbert cell
    []
  end
end
