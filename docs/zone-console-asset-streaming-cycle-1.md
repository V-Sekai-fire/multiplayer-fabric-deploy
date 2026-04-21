# Cycle 1 — `UroClient.login/3`

**Status:** [ ] RED  
**Effort:** Low  
**Back:** [index](zone-console-asset-streaming.md)

## What you get

`UroClient.login/3` authenticates against the live uro backend at
`https://uro.chibifire.com` and returns a bearer token. Every subsequent cycle
depends on this token.

## Infrastructure

Cloudflare proxies `uro.chibifire.com` → Fly.io app `multiplayer-fabric-uro`
(region `yyz`). TLS terminates at Cloudflare; the Fly machine is never exposed
directly. The `/session` endpoint is public (no prior token required).

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
end
```

Run with:

```sh
cd multiplayer-fabric-zone-console
URO_BASE_URL=https://uro.chibifire.com \
URO_EMAIL=... \
URO_PASSWORD=... \
mix test --only prod test/zone_console/uro_client_login_test.exs
```

Expected failure before implementation: `** (KeyError) key "URO_BASE_URL" not found` or
HTTP 4xx if credentials are wrong.

## GREEN — pass condition

The test passes. `authed.access_token` is a non-empty string. `authed.user` is
a map containing at least a `"username"` key.

Verify manually:

```sh
curl -s -X POST https://uro.chibifire.com/session \
  -H "Content-Type: application/json" \
  -d '{"user":{"email":"<email>","password":"<pw>"}}' | jq .
```

## REFACTOR

No structural changes needed for this cycle. `UroClient.login/3` already exists
in `zone_console/uro_client.ex`. The test is the deliverable.

## Fly.io check

```sh
fly logs --app multiplayer-fabric-uro | grep "POST /session"
```

Confirm the request appears in Fly.io logs, proving it reached the machine and
was not short-circuited at Cloudflare.
