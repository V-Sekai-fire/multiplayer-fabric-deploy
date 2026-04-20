# Cycle 8 — Playwright + AccessKit browser smoke test

**Status:** [ ] not started  
**Effort:** High  
**Depends on:** Cycles 6 and 7  
**Back:** [index](zone-console-asset-streaming.md)

## What you get

An automated Playwright test that connects to `zone_console`'s WebTransport
console server from the browser, uploads `mire.tscn`, sends
`CMD_INSTANCE_ASSET`, and verifies the instanced node appears in the browser's
AccessKit accessibility tree.

## Preconditions

- Full Fly.io/FLAME stack running (or local Docker equivalent).
- Godot web export built with `gescons` (`accesskit=yes` already set) and served.
- `zone_console` running natively on macOS.

## Console WebTransport server

`zone_console` starts a WebTransport server on `CONSOLE_PORT` (default 4433).
The browser opens one persistent bidirectional stream per session; commands are 
newline-terminated strings and responses are newline-terminated `ok: ...` / 
`error: ...` lines.

## Console WebTransport server

`zone_console` starts a WebTransport server on `CONSOLE_PORT` (default 4433)
when `CONSOLE_CERTFILE` and `CONSOLE_KEYFILE` are set.  The browser opens one
persistent bidirectional stream per session; commands are newline-terminated
strings and responses are newline-terminated `ok: ...` / `error: ...` lines.

The server is implemented in `ZoneConsole.ConsoleConnectionHandler` and
`ZoneConsole.ConsoleStreamHandler` using the existing `wtransport` dependency —
no new dependencies.

## Playwright config (`playwright.config.ts`)

```typescript
import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { homedir } from 'node:os';
import { join } from 'node:path';

function consoleCertHash(): ArrayBuffer {
  const pem = readFileSync(join(homedir(), '.config', 'zone_console', 'console.crt'), 'utf8');
  const b64 = pem.replace(/-----[^-]+-----/g, '').replace(/\s/g, '');
  const der = Buffer.from(b64, 'base64');
  return createHash('sha256').update(der).digest().buffer;
}

export default {
  use: {
    // cert hash computed locally from the cert zone_console wrote on login —
    // no uro query, no credentials in the test
    webTransportCertHash: consoleCertHash(),
  },
};
```

## Test script (`tests/e2e/test_asset_streaming.spec.ts`)

```typescript
import { test, expect } from '@playwright/test';

test('instance mire scene near player via WebTransport', async ({ page }) => {
  // 1. Load Godot web client and wait for AccessKit root
  await page.goto('http://localhost:8060');
  await page.getByRole('application', { name: 'Godot Engine' }).waitFor();

  // 2. Connect to zone_console WebTransport console server from the browser.
  //    Hash comes from playwright.config.ts (read from ~/.config/zone_console/console.crt).
  //    All commands share one bidi stream so zone_client persists across them.
  const certHash: ArrayBuffer = (test.info() as any).project.use.webTransportCertHash;
  const port = parseInt(process.env.CONSOLE_PORT ?? '4433');

  const result = await page.evaluate(
    async ({ certHash, port }) => {
    const transport = new WebTransport(`https://localhost:${port}/console`, {
      serverCertificateHashes: [{ algorithm: 'sha-256', value: certHash }],
    });
    await transport.ready;

    const { readable, writable } = await transport.createBidirectionalStream();
    const writer = writable.getWriter();
    const reader = readable.getReader();
    const enc = (s: string) => new TextEncoder().encode(s);

    let buf = '';
    async function readLine(): Promise<string> {
      while (!buf.includes('\n')) {
        const { done, value } = await reader.read();
        if (done) break;
        buf += new TextDecoder().decode(value);
      }
      const nl = buf.indexOf('\n');
      const line = buf.slice(0, nl);
      buf = buf.slice(nl + 1);
      return line;
    }

    async function cmd(text: string): Promise<string> {
      await writer.write(enc(text + '\n'));
      return readLine();
    }

    await cmd('join 0');
    const uploadResp = await cmd(
      'upload multiplayer-fabric-humanoid-project/humanoid/scenes/mire.tscn'
    );
    const assetId = uploadResp.match(/as (\d+)/)?.[1];
    if (!assetId) throw new Error('Upload failed: ' + uploadResp);

    await cmd(`instance ${assetId} 0.0 1.0 0.0`);
    transport.close();
    return uploadResp;
  }, { certHash, port });

  // 4. Verify AccessKit tree reflects the instanced mire node
  const node = page.getByRole('group', { name: 'mire' });
  await expect(node).toBeVisible({ timeout: 15_000 });
});
```

## Authority note

The browser connects to the zone server via WebTransport (game client).
The zone server routes `CMD_INSTANCE_ASSET` to the authority zone for
`hilbert3D(0, 1, 0)`.  The AccessKit tree update originates from the web
client receiving the CH_INTEREST ghost — not from a direct instance on the
client side.

## Platform note

`zone_console` runs natively on macOS.  The zone server and uro run in Docker
(Linux containers).  The console WebTransport server (`localhost:4433`) is
hosted by `zone_console` itself — no Docker required for that endpoint.

## Pass condition

`getByRole('group', { name: 'mire' })` becomes visible within 15 s of the
`instance` command.  This confirms the full pipeline:

```
S3 upload → uro manifest → CMD_INSTANCE_ASSET packet
  → authority zone handler → CH_INTEREST ghost broadcast
  → WebTransport push to web client → scene instantiation
  → AccessKit tree update → Playwright assertion passes
```
