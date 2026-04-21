# Zone console asset streaming

Upload a raw asset (GLB or .tscn) from `zone_console` to uro, trigger the
[ephemeral bake](ephemeral-asset-bake-microservice.md) when needed, then
instance it in the live world via `CMD_INSTANCE_ASSET`.

## Infrastructure

| Layer        | Service                              | Host                              |
| ------------ | ------------------------------------ | --------------------------------- |
| DNS / TLS    | Cloudflare proxy                     | uro.chibifire.com                 |
| API backend  | multiplayer-fabric-uro (Phoenix)     | Fly.io app `multiplayer-fabric-uro` region `yyz` |
| Object store | Tigris (S3-compatible via Fly.io)    | bucket `uro-uploads`              |
| Zone servers | multiplayer-fabric-zones (Godot)     | Fly.io app `multiplayer-fabric-zones` region `yyz` |
| Database     | CockroachDB single-node              | Fly.io app `multiplayer-fabric-crdb` region `yyz` |

`zone_console` runs natively on macOS. All other components run on Fly.io.
Web/Browser support is not a target.

## Authoritative design

1. Authority — the zone whose Hilbert range contains `hilbert3D(pos)` receives
   and executes `CMD_INSTANCE_ASSET`. No other zone instances the scene.
2. Interest — neighbouring zones within `AOI_CELLS` receive a CH_INTEREST
   ghost. They do not re-fetch or re-instance.
3. ReBAC — the authority zone evaluates `rebacCheck` before instancing.
   `observe` is public; `modify` requires `owner`.
4. Headless baking — production zone servers carry no editor code. All
   `.tscn` / `.godot/imported` generation happens in the ephemeral baker.
5. Elastic orchestration — Uro acts as the FLAME parent. Zone servers and
   asset bakers are FLAME runners on Fly.io.

## RED-GREEN-REFACTOR rules

Every cycle follows the same three-step arc:

RED — write one or more ExUnit tests that fail. The failure message must be
specific enough to prove the assertion is load-bearing.

GREEN — write the minimum code to make those tests pass. No extra abstractions.

REFACTOR — clean up with tests still green. One commit per arc.

Pass conditions for cycles 1-5 run against the Fly.io stack using the env
vars below. Cycles 6-10 additionally require the zone server container.

```
URO_BASE_URL=https://uro.chibifire.com
URO_EMAIL=<operator email>
URO_PASSWORD=<operator password>
ZONE_SERVER_URL=https://zone-700a.chibifire.com
ZONE_CERT_PIN=<cert fingerprint>
TEST_SCENE_PATH=multiplayer-fabric-humanoid-project/humanoid/scenes/mire.tscn
AWS_S3_BUCKET=uro-uploads
AWS_S3_ENDPOINT=https://fly.storage.tigris.dev
AWS_ACCESS_KEY_ID=<tigris key>
AWS_SECRET_ACCESS_KEY=<tigris secret>
```

Cloudflare terminates TLS for `uro.chibifire.com`. Requests reach the Fly.io
machine over the internal network. Certificate pinning for zone servers uses
the Fly.io machine certificate, not a Cloudflare-issued one.

## Cycles

| Cycle | What you get                                                           | Effort | Status |
| ----- | ---------------------------------------------------------------------- | ------ | ------ |
| 1     | `UroClient.login/3` — authenticate against prod uro                   | Low    | [ ]    |
| 2     | `UroClient.upload_asset/3` — chunk → Tigris → uro manifest            | Medium | [ ]    |
| 3     | `UroClient.get_manifest/2` — fetch chunk manifest from prod           | Low    | [ ]    |
| 4     | `CMD_INSTANCE_ASSET` wire encoding — 100-byte packet verified         | Low    | [ ]    |
| 5     | `instance` console command — sends packet to zone server              | Low    | [ ]    |
| 6     | FLAME asset baker — ephemeral `editor=yes` import on Fly.io           | Medium | [ ]    |
| 7     | FLAME zone orchestrator — elastic `editor=no` placement on Fly.io     | High   | [ ]    |
| 8     | Godot zone handler — authority zone runs instance pipeline            | High   | [ ]    |
| 9     | Round-trip smoke test — upload → instance → entity list on prod       | High   | [ ]    |
| 10    | Multi-platform verification — macOS + Linux + Windows, AccessKit      | High   | [ ]    |
