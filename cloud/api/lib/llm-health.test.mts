import assert from 'node:assert/strict';
import test from 'node:test';

import { getLlmRuntimeStatus, resolveLlmRuntimeHealthConfig } from './llm-health.ts';

const ORIGINAL_ENV = { ...process.env };
const ORIGINAL_FETCH = globalThis.fetch;

test.afterEach(() => {
  for (const key of Object.keys(process.env)) {
    if (!(key in ORIGINAL_ENV)) {
      delete process.env[key];
    }
  }

  for (const [key, value] of Object.entries(ORIGINAL_ENV)) {
    process.env[key] = value;
  }

  globalThis.fetch = ORIGINAL_FETCH;
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

test('getLlmRuntimeStatus reports AiHubMix as unavailable when probe returns placeholder content', async () => {
  process.env.LLM_PROVIDER = 'aihubmix';
  process.env.AIHUBMIX_API_KEY = 'test-key';
  process.env.AIHUBMIX_MODEL = 'gemini-3-flash-preview';
  process.env.AIHUBMIX_BASE_URL = 'https://example.com/v1';
  process.env.AIHUBMIX_PATH = '/chat/completions';

  globalThis.fetch = async () =>
    new Response(
      JSON.stringify({
        choices: [{ message: { content: 'thought' } }],
      }),
      {
        status: 200,
        headers: { 'Content-Type': 'application/json' },
      }
    );

  const status = await getLlmRuntimeStatus();

  assert.equal(status.provider, 'aihubmix');
  assert.equal(status.ready, false);
  assert.match(status.message, /连通性检查失败/);
});

test('getLlmRuntimeStatus does not treat legacy OPENAI env vars as valid configuration', async () => {
  process.env.LLM_PROVIDER = 'aihubmix';
  process.env.OPENAI_API_KEY = 'legacy-key';
  process.env.OPENAI_MODEL = 'legacy-model';
  process.env.OPENAI_BASE_URL = 'https://legacy.example.com/v1';
  process.env.OPENAI_PATH = '/chat/completions';

  const status = await getLlmRuntimeStatus();

  assert.equal(status.configured, false);
  assert.equal(status.provider, 'none');
  assert.equal(status.model, null);
  assert.match(status.message, /未配置可用 LLM/);
});
