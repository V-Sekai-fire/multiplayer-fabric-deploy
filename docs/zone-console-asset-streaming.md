# Zone console asset streaming

Upload a raw asset (GLB or .tscn) from `zone_console` to uro, trigger the
ephemeral bake when needed, then instance it in the live world via
`CMD_INSTANCE_ASSET`.

## Infrastructure

The entire stack runs on a single host machine. Cloudflare connects it to
the public internet.

```
Internet
  │
  ▼
Cloudflare edge (TLS termination, HTTP/1.1 proxy)
  │  hub-700a.chibifire.com → Cloudflare Tunnel
  │
  ▼
cloudflared (Docker, tunnel token)
  │  routes hub-700a.chibifire.com → http://zone-backend:4000
  ▼
zone-backend:4000  (Phoenix / Uro, Docker)
  ├── crdb:26257   (CockroachDB, Docker, ghcr.io/v-sekai/cockroach)
  └── versitygw:7070 (S3-compatible object store, Docker)

zone-700a.chibifire.com
  │  Cloudflare DNS A record → host machine public IP (173.180.240.105)
  │  Port 443 UDP forwarded at router to host machine
  ▼
zone-server:443/udp  (Godot headless, Docker)
  └── native WebTransport / picoquic (NOT proxied by Cloudflare)
```

### Key points

Cloudflare Tunnel carries all HTTP/1.1 traffic for `hub-700a.chibifire.com`.
TLS terminates at the Cloudflare edge — the tunnel sends plain HTTP/1.1 to
`zone-backend:4000` on the host's Docker network.

`zone-700a.chibifire.com` is a plain DNS A record pointing to the host machine's
public IP. The router forwards UDP 443 to the host. Cloudflare does not proxy
UDP — zone server traffic is direct to the host, TLS is the Godot-issued
self-signed certificate pinned by `ZONE_CERT_HASH_B64`.

Object storage uses VersityGW (local POSIX-backed S3) behind `versitygw:7070`
on the Docker internal network. Zone-backend reads `AWS_S3_ENDPOINT=http://versitygw:7070`.

### Environment file

All secrets live in `multiplayer-fabric-hosting/.env`:

```
CLOUDFLARE_TUNNEL_TOKEN=<tunnel token>
URL=https://hub-700a.chibifire.com/api/v1/
ROOT_ORIGIN=https://hub-700a.chibifire.com
FRONTEND_URL=https://hub-700a.chibifire.com/
ZONE_HOST=zone-700a.chibifire.com
ZONE_PORT=443
ZONE_CERT_HASH_B64=<base64 of zone server cert SHA-256>
AWS_S3_BUCKET=uro-uploads
AWS_S3_ENDPOINT=http://versitygw:7070
AWS_ACCESS_KEY_ID=minioadmin
AWS_SECRET_ACCESS_KEY=<secret>
```

### Start the stack

```sh
cd multiplayer-fabric-hosting
docker compose up -d
```

Services started: `crdb`, `versitygw`, `versitygw-init`, `zone-backend`,
`cloudflared`, `zone-server`.

### Smoke-check the stack

```sh
# uro health (via Cloudflare Tunnel)
curl -s https://hub-700a.chibifire.com/health
# expect: {"services":{"uro":"healthy"}}

# uro health (direct, bypassing Cloudflare)
curl -s http://localhost:4000/health
# expect: {"services":{"uro":"healthy"}}

# CockroachDB admin UI (direct)
open http://localhost:8181

# VersityGW S3 (direct)
curl -s http://localhost:7070/ | head -3
```

## Authoritative design

1. Authority — the zone whose Hilbert range contains `hilbert3D(pos)` receives
   and executes `CMD_INSTANCE_ASSET`. No other zone instances the scene.
2. Interest — neighbouring zones within `AOI_CELLS` receive a CH_INTEREST
   ghost. They do not re-fetch or re-instance.
3. ReBAC — the authority zone evaluates `rebacCheck` before instancing.
   `observe` is public; `modify` requires `owner`.
4. Headless baking — zone servers carry no editor code. Asset baking runs as
   a Docker service (`editor=yes`) on the same host.
5. Object storage — chunks stored in VersityGW (local S3) via `versitygw:7070`.

## RED-GREEN-REFACTOR rules

Every cycle follows three steps:

RED — write one or more ExUnit tests that fail with a specific, load-bearing
error message.

GREEN — write the minimum code to make those tests pass. No extra abstractions.

REFACTOR — clean up with tests still green. One commit per arc.

Pass conditions for cycles 1-5 target `https://hub-700a.chibifire.com` via
the Cloudflare Tunnel. Cycles 6-10 also require the zone server container.

Test env vars:

```
URO_BASE_URL=https://hub-700a.chibifire.com
URO_EMAIL=<operator email>
URO_PASSWORD=<operator password>
ZONE_SERVER_URL=https://zone-700a.chibifire.com
ZONE_CERT_PIN=<zone server cert SHA-256 fingerprint>
TEST_SCENE_PATH=../multiplayer-fabric-humanoid-project/humanoid/scenes/mire.tscn
AWS_S3_BUCKET=uro-uploads
AWS_S3_ENDPOINT=http://localhost:7070
AWS_ACCESS_KEY_ID=minioadmin
AWS_SECRET_ACCESS_KEY=<secret>
```

## Cycles

| Cycle | What you get                                                           | Effort | Status |
| ----- | ---------------------------------------------------------------------- | ------ | ------ |
| 1     | `UroClient.login/3` — authenticate against prod uro                   | Low    | [x]    |
| 2     | `UroClient.upload_asset/3` — chunk → VersityGW → uro manifest         | Medium | [x]    |
| 3     | `UroClient.get_manifest/2` — fetch chunk manifest from prod           | Low    | [x]    |
| 4     | `CMD_INSTANCE_ASSET` wire encoding — 100-byte packet verified         | Low    | [x]    |
| 5     | `instance` console command — sends packet to zone server              | Low    | [x]    |
| 6     | Asset baker — Docker `editor=yes` headless import on host             | Medium | [ ]    |
| 7     | Zone orchestrator — Docker `editor=no` zone server lifecycle          | High   | [ ]    |
| 8     | Godot zone handler — authority zone runs instance pipeline            | High   | [ ]    |
| 9     | Round-trip smoke test — upload → instance → entity list on prod       | High   | [ ]    |
| 10    | Multi-platform verification — macOS + Linux + Windows, AccessKit      | High   | [ ]    |
