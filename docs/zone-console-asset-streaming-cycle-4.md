# Cycle 4 — `instance <asset_id> <x> <y> <z>` command

**Status:** [x] done  
**Effort:** Low  
**Back:** [index](zone-console-asset-streaming.md)

## What you get

The `instance` command in `zone_console` lets a user trigger asset instancing
at a specific position in the world.

## Implementation

`multiplayer-fabric-zone-console/lib/zone_console/app.ex`:

```elixir
defp run_command(state, "instance " <> args) do
  case String.split(String.trim(args)) do
    [id_str, x_str, y_str, z_str] ->
      with {id, ""} <- Integer.parse(id_str),
           {x, ""} <- Float.parse(x_str),
           {y, ""} <- Float.parse(y_str),
           {z, ""} <- Float.parse(z_str) do
        if state.zone_client do
          ZoneClient.send_instance(state.zone_client, id, x, y, z)
          append(state, line(:ok, "Instance request sent for asset #{id} at (#{x}, #{y}, #{z})"))
        else
          append(state, line(:warn, "Not joined to a zone. Run 'join' first."))
        end
      else
        _ -> append(state, line(:err, "usage: instance <asset_id> <x> <y> <z>  (int, floats)"))
      end

    _ ->
      append(state, line(:err, "usage: instance <asset_id> <x> <y> <z>"))
  end
end
```

## Authority routing

The position `(x, y, z)` determines which zone has authority.  The console
sends the packet to the connected zone server; that server forwards it to the
authority zone for `hilbert3D(x, y, z)`.  The authority zone performs the
actual instancing (Cycle 6).

## Pass condition

`instance <id> 0.0 1.0 0.0` prints `Instance request sent for asset <id> at (0.0, 1.0, 0.0)`
and the zone server receives the packet (observable in server logs).
