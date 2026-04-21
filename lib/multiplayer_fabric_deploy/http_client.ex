defmodule MultiplayerFabricDeploy.HTTPClient do
  @moduledoc """
  HTTP client wrapper for making requests to uro and other services.
  Uses :httpc from Erlang standard library.
  """

  def get(url, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 30_000)

    headers = [{~c"User-Agent", ~c"multiplayer-fabric-deploy/1.0"}]

    case :httpc.request(:get, {String.to_charlist(url), headers}, [timeout: timeout], []) do
      {:ok, {{_version, status, _reason}, _headers, body}} when status in [200, 201, 204] ->
        {:ok, %{status: status, body: body}}

      {:ok, {{_version, status, _reason}, _headers, body}} ->
        {:error, {:http_error, status, body}}

      {:error, reason} ->
        {:error, {:connection_error, reason}}
    end
  rescue
    e -> {:error, {:http_exception, inspect(e)}}
  end

  def post(url, body, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 30_000)
    content_type = Keyword.get(opts, :content_type, ~c"application/json")

    headers = [
      {~c"User-Agent", ~c"multiplayer-fabric-deploy/1.0"},
      {~c"Content-Type", content_type}
    ]

    body_str = if is_map(body), do: Jason.encode!(body), else: body

    case :httpc.request(:post, {String.to_charlist(url), headers, content_type, body_str},
                        [timeout: timeout], []) do
      {:ok, {{_version, status, _reason}, _headers, response_body}} when status in [200, 201, 204] ->
        {:ok, %{status: status, body: response_body}}

      {:ok, {{_version, status, _reason}, _headers, response_body}} ->
        {:error, {:http_error, status, response_body}}

      {:error, reason} ->
        {:error, {:connection_error, reason}}
    end
  rescue
    e -> {:error, {:http_exception, inspect(e)}}
  end
end
