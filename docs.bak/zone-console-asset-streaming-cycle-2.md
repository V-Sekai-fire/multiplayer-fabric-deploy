# Cycle 2 — UroClient.upload_asset/3

**Status:** [x] done  
**Effort:** Medium  
**Back:** [index](zone-console-asset-streaming.md)

## What you get

`UroClient.upload_asset/3` chunks the scene file via casync, uploads chunks
to S3 (VersityGW), and registers a manifest with uro.

## Implementation

`multiplayer-fabric-zone-console/lib/zone_console/uro_client.ex`.  
Dependency `{:aria_storage, github: "V-Sekai-fire/aria-storage"}` in
`multiplayer-fabric-zone-console/mix.exs`.

1. `AriaStorage.process_file(path, backend: :s3)` → `{:ok, %{chunks, store_url}}`
2. POST `/storage` with `{name, chunks, store_url}` + Bearer token
3. Return `{:ok, id}`

S3 configured in `multiplayer-fabric-zone-console/config/runtime.exs`:

```elixir
config :aria_storage,
  storage_backend: :s3,
  s3_bucket: System.get_env("AWS_S3_BUCKET", "uro-uploads"),
  s3_endpoint: System.get_env("AWS_S3_ENDPOINT", "http://localhost:7070"),
  aws_access_key_id: System.get_env("AWS_ACCESS_KEY_ID"),
  aws_secret_access_key: System.get_env("AWS_SECRET_ACCESS_KEY")
```

## Pass condition

`UroClient.upload_asset/3` returns `{:ok, id}` and the asset id is queryable
via `GET /storage/:id` on the uro API.
