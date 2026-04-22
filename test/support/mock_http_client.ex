defmodule MultiplayerFabricDeploy.MockHTTPClient do
  @moduledoc """
  Mock HTTP client for testing. Returns canned responses based on URL pattern.
  """

  def get(url, _opts \\ []) do
    cond do
      # Mock manifest fetch from uro
      String.contains?(url, "/storage/") and String.contains?(url, "/manifest") ->
        {:ok,
         %{
           status: 200,
           body:
             Jason.encode!(%{
               "chunks" => ["chunk-1", "chunk-2"],
               "store_url" => "https://store.example.com"
             })
         }}

      # Mock chunk downloads from storage
      String.contains?(url, "/chunk-") ->
        chunk_id = extract_chunk_id(url)

        {:ok,
         %{
           status: 200,
           body: "chunk-data-#{chunk_id}"
         }}

      # Mock entity list
      String.contains?(url, "/api/entities") ->
        {:ok,
         %{
           status: 200,
           body:
             Jason.encode!(%{
               "entities" => [
                 %{"id" => 1, "position" => [0.0, 1.0, 0.0], "type" => "scene"},
                 %{"id" => 2, "position" => [1.0, 2.0, 3.0], "type" => "ghost"}
               ]
             })
         }}

      # Default 404
      true ->
        {:error, {:http_error, 404, "Not found"}}
    end
  rescue
    e -> {:error, {:http_exception, inspect(e)}}
  end

  def post(url, body, _opts \\ []) do
    cond do
      # Mock asset upload
      String.contains?(url, "/api/assets/upload") ->
        {:ok,
         %{
           status: 201,
           body:
             Jason.encode!(%{
               "asset_id" => "550e8400-e29b-41d4-a716-446655440000"
             })
         }}

      # Default error
      true ->
        {:error, {:http_error, 404, "Not found"}}
    end
  rescue
    e -> {:error, {:http_exception, inspect(e)}}
  end

  defp extract_chunk_id(url) do
    url
    |> String.split("/")
    |> List.last()
    |> String.trim()
  end
end
