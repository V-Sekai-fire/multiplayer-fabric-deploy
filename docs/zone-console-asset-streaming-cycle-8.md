# Cycle 8 — Playwright + AccessKit browser smoke test

**Status:** [ ] not started  
**Effort:** High  
**Depends on:** Cycles 6 and 7  
**Back:** [index](zone-console-asset-streaming.md)

## What you get

An automated Playwright test that drives `zone_console` to upload a scene,
sends `CMD_INSTANCE_ASSET` via WebTransport, and verifies the instanced node
appears in the browser's AccessKit accessibility tree next to the player.

## Preconditions

- Full Docker stack running: `cd multiplayer-fabric-hosting && docker compose up -d`
- Godot web export built with `gescons` (`accesskit=yes` already set) and served:
  ```sh
  npx serve bin/ --listen 8060
  ```
- `zone_console` running natively on macOS and joined to the zone

## Test fixture

`tests/fixtures/minimal.tscn` — single `MeshInstance3D` root node named `minimal`,
no scripts.  The root node name is what AccessKit surfaces as the accessible group name.

## Test script (`tests/e2e/test_asset_streaming.spec.ts`)

```typescript
import { test, expect } from '@playwright/test';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';

const exec = promisify(execFile);

async function consoleCmd(cmd: string): Promise<string> {
  const { stdout } = await exec('zone_console', ['--cmd', cmd]);
  return stdout;
}

test('instance scene near player via WebTransport', async ({ page }) => {
  // 1. Load Godot web client and wait for AccessKit root
  await page.goto('http://localhost:8060');
  await page.getByRole('application', { name: 'Godot Engine' }).waitFor();

  // 2. Join zone
  await consoleCmd('join zone-700a.chibifire.com');

  // 3. Upload scene to desync S3 via uro
  const uploadOut = await consoleCmd('upload tests/fixtures/minimal.tscn');
  const assetId = uploadOut.match(/as (\d+)/)?.[1];
  if (!assetId) throw new Error(`Upload failed: ${uploadOut}`);

  // 4. Send CMD_INSTANCE_ASSET via WebTransport
  await consoleCmd(`instance ${assetId} 0.0 1.0 0.0`);

  // 5. Verify AccessKit tree reflects the instanced node next to player
  const node = page.getByRole('group', { name: 'minimal' });
  await expect(node).toBeVisible({ timeout: 15_000 });
});
```

## Authority note

The web client connects to the zone server via WebTransport.  The zone server
routes `CMD_INSTANCE_ASSET` to the authority zone for `hilbert3D(0, 1, 0)`.
The AccessKit tree update originates from the web client receiving the
CH_INTEREST ghost broadcast from the authority zone — not from a direct
instance on the client side.

## AccessKit note

`gescons` already passes `accesskit=yes` to SCons.  Use a descriptive root
node name in production scenes so the accessibility tree remains meaningful.

## Pass condition

`getByRole('group', { name: 'minimal' })` becomes visible within 15 s of the
`instance` command.  This confirms the full pipeline:

```
S3 upload → uro manifest → CMD_INSTANCE_ASSET packet
  → authority zone handler → CH_INTEREST ghost broadcast
  → WebTransport push to web client → scene instantiation
  → AccessKit tree update → Playwright assertion passes
```
