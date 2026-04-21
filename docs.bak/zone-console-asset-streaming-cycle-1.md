# Cycle 1 — `upload <path>` command

**Status:** [x] done  
**Effort:** Low  
**Back:** [index](zone-console-asset-streaming.md)

## What you get

The `upload <path>` command in `zone_console` lets a user store a Godot scene
in uro and receive an asset id for later instancing.

## Implementation

`multiplayer-fabric-zone-console/lib/zone_console/app.ex`:

```elixir
defp run_command(state, "upload " <> path) do
  path = String.trim(path)
  name = Path.basename(path)

  case UroClient.upload_asset(state.uro, path, name) do
    {:ok, id} ->
      append(state, line(:ok, "Uploaded #{name} as #{id}"))

    {:error, reason} ->
      append(state, line(:err, "Upload failed: #{reason}"))
  end
end
```

## Pass condition

`upload path/to/scene.tscn` prints `Uploaded scene.tscn as <id>` with a
non-empty id.
