# Ephemeral asset baking (Docker one-shot)

When a raw asset is uploaded to uro, a one-shot Docker container running the
Godot editor binary (`editor=yes` build) performs the headless import and
returns the baked artefact via the casync format. Zone servers carry no editor
code.

## Flow

```
POST /storage (raw asset uploaded by zone_console)
  ↓
zone-backend spawns baker container (one-shot, exits when done):
  docker run --rm \
    --network multiplayer-fabric-hosting_default \
    -v /tmp/scene-<id>:/scene \
    -e ASSET_ID=<id> \
    -e URO_URL=http://zone-backend:4000 \
    -e VERSITYGW_URL=http://versitygw:7070 \
    multiplayer-fabric-godot-baker:latest
  ↓
baker container:
  godot --headless --path /scene --import
  # chunk .godot/imported/ via AriaStorage casync
  AriaStorage.ChunkUploader.chunk_directory("/scene/.godot/imported")
    → uploads .cacnk files to versitygw:7070/uro-uploads/chunks/<ab>/<cd>/<hash>.cacnk
  AriaStorage.Index.write_caidx(chunks, "/out/<id>.caidx")
    → uploads /out/<id>.caidx to versitygw:7070/uro-uploads/<id>.caidx
  POST http://zone-backend:4000/storage/<id>/bake
       {baked_url: "http://versitygw:7070/uro-uploads/<id>.caidx"}
  exit 0
  ↓
zone-backend writes baked_url to CockroachDB shared_files record
```

## casync format

Chunks are content-addressed SHA512/256 blobs stored as `.cacnk` files.
The index (`.caidx`) is a directory-tree manifest that lists each chunk's
hash and byte offset. Zone clients reconstruct `.godot/imported/` by:
1. Fetching the `.caidx` index from the `baked_url`
2. Fetching only missing `.cacnk` chunks (delta sync)
3. Writing chunks to the local cache

AriaStorage provides the Elixir API for both baker and zone-console sides.

## Baker image

Built from `multiplayer-fabric-godot/Dockerfile.baker`, target `baker`.
SCons flags: `editor=yes scons_cache_limit=4096 linuxbsd headless`.

```sh
cd multiplayer-fabric-godot
docker build --target baker \
  -t multiplayer-fabric-godot-baker:latest \
  -f Dockerfile.baker .
```

## Security model

The baker container connects only to the Docker-internal network
(`multiplayer-fabric-hosting_default`). It cannot reach the public internet.
It authenticates to zone-backend using an internal service token passed via
environment variable, not a user OAuth token.

## Operational monitoring

Baker container logs are readable via:

```sh
docker ps -a --filter ancestor=multiplayer-fabric-godot-baker:latest
docker logs <baker-container-id>
```

Zone-backend logs show bake trigger and result:

```sh
docker logs multiplayer-fabric-hosting-zone-backend-1 2>&1 | grep "bake"
```

## Benefits

- Zone server Docker image is smaller by ~150 MB (no editor code).
- Every zone uses the same baked BVH structure — no import parameter drift.
- casync delta sync means zone clients only download changed chunks on update.
- Baking is isolated: a crash in the baker does not affect zone servers.
- No cloud provider required — runs on the same host machine as the rest of
  the stack.
