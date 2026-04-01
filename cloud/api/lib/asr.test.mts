import assert from 'node:assert/strict';
import test from 'node:test';

import { resolveAsrProxyHealthPath } from './asr.ts';

const ORIGINAL_ENV = { ...process.env };

test.afterEach(() => {
  for (const key of Object.keys(process.env)) {
    if (!(key in ORIGINAL_ENV)) {
      delete process.env[key];
    }
  }

  for (const [key, value] of Object.entries(ORIGINAL_ENV)) {
    process.env[key] = value;
  }
});

test('resolveAsrProxyHealthPath keeps the ASR proxy health route under /asr-proxy', () => {
  process.env.ASR_PROXY_HEALTH_PATH = '/healthz';

  assert.equal(resolveAsrProxyHealthPath(), '/asr-proxy/healthz');
});
