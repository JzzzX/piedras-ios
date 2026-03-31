import assert from 'node:assert/strict';
import test from 'node:test';

import { resolveLlmRuntimeHealthConfig } from './llm-health.ts';

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

test('resolveLlmRuntimeHealthConfig reads timeout and cache TTL env vars', () => {
  process.env.LLM_STATUS_PROBE_TIMEOUT_MS = '2500';
  process.env.LLM_STATUS_SUCCESS_TTL_MS = '120000';
  process.env.LLM_STATUS_FAILURE_TTL_MS = '15000';

  assert.deepEqual(resolveLlmRuntimeHealthConfig(), {
    probeTimeoutMs: 2500,
    successTtlMs: 120000,
    failureTtlMs: 15000,
  });
});
