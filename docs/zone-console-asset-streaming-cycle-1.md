# Cycle 1 — `UroClient.login/3`

**Status:** [ ] RED  
**Effort:** Low  
**Back:** [index](zone-console-asset-streaming.md)

## What you get

`UroClient.login/3` authenticates against the live uro backend at
`https://hub-700a.chibifire.com` and returns a bearer token. Every
subsequent cycle depends on this token.

## Infrastructure path

```
zone_console (macOS)
  → HTTPS POST /session
  → Cloudflare edge (TLS termination)
  → Cloudflare Tunnel (HTTP/1.1)
  → cloudflared container
  → zone-backend:4000 (Phoenix)
  → returns Bearer token
```

Cloudflare terminates TLS. The tunnel sends plain HTTP/1.1 to
`zone-backend:4000` on the Docker network. No certificate handling
needed in the client — standard HTTPS via system CA.

## RED — failing test

File: `test/zone_console/uro_client_login_test.exs`

```elixir
defmodule ZoneConsole.UroClientLoginTest do
  use ExUnit.Case, async: false

  @tag :prod
  test "login returns bearer token from prod uro" do
    base_url = System.fetch_env!("URO_BASE_URL")
    email    = System.fetch_env!("URO_EMAIL")
    password = System.fetch_env!("URO_PASSWORD")

    client = ZoneConsole.UroClient.new(base_url)
    {:ok, authed} = ZoneConsole.UroClient.login(client, email, password)

    assert is_binary(authed.access_token)
    assert byte_size(authed.access_token) > 0
    assert is_map(authed.user)
  end

  @tag :prod
  test "login with wrong password returns error tuple, not raise" do
    client = ZoneConsole.UroClient.new(System.fetch_env!("URO_BASE_URL"))
    result = ZoneConsole.UroClient.login(client, "nobody@example.com", "wrong")
    assert match?({:error, _}, result)
  end
end
```

Run:

```sh
cd multiplayer-fabric-zone-console
URO_BASE_URL=https://hub-700a.chibifire.com \
URO_EMAIL=... URO_PASSWORD=... \
mix test --only prod test/zone_console/uro_client_login_test.exs
```

## GREEN — pass condition

Both tests pass.

Verify the stack received the request:

```sh
# Cloudflare edge — check CF-Ray in response headers
curl -sI -X POST https://hub-700a.chibifire.com/session \
  -H "Content-Type: application/json" \
  -d '{"user":{"email":"...","password":"..."}}' | grep -i cf-ray

# cloudflared container — request appears in tunnel logs
docker logs multiplayer-fabric-hosting-cloudflared-1 2>&1 | grep "POST /session"

# zone-backend — Phoenix log line
docker logs multiplayer-fabric-hosting-zone-backend-1 2>&1 | grep "POST /session"
```

## REFACTOR

`UroClient.login/3` is already implemented. The test is the deliverable.
Ensure the file is in `test/zone_console/` and tagged `:prod` so it is
excluded from the default `mix test` run.

## Cloudflare Tunnel note

The tunnel ingress config routes `hub-700a.chibifire.com →
http://zone-backend:4000`. If the CF dashboard has the origin set to
HTTPS, the tunnel will fail with a TLS handshake error. Set origin protocol
to **HTTP** in the tunnel Public Hostname settings.

Confirm the tunnel is healthy:

```sh
docker logs multiplayer-fabric-hosting-cloudflared-1 2>&1 | grep "Registered tunnel"
# expect 4 lines, one per edge connection
```
