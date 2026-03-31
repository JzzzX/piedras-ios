import assert from 'node:assert/strict';
import test from 'node:test';

import { generateTextWithFallback } from './llm-provider.ts';

const ORIGINAL_ENV = { ...process.env };
const ORIGINAL_FETCH = globalThis.fetch;

function resetEnv() {
  for (const key of Object.keys(process.env)) {
    if (!(key in ORIGINAL_ENV)) {
      delete process.env[key];
    }
  }

  for (const [key, value] of Object.entries(ORIGINAL_ENV)) {
    process.env[key] = value;
  }
}

function configureOpenAIProvider() {
  process.env.LLM_PROVIDER = 'openai';
  process.env.OPENAI_API_KEY = 'test-key';
  process.env.OPENAI_MODEL = 'test-model';
  process.env.OPENAI_BASE_URL = 'https://example.com/v1';
  process.env.OPENAI_PATH = '/chat/completions';
}

test.afterEach(() => {
  resetEnv();
  globalThis.fetch = ORIGINAL_FETCH;
});

test('generateTextWithFallback retries transient openai failures once', async () => {
  configureOpenAIProvider();

  let calls = 0;
  globalThis.fetch = async () => {
    calls += 1;
    if (calls == 1) {
      throw new Error('network timeout');
    }

    return new Response(
      JSON.stringify({
        choices: [{ message: { content: 'OK' } }],
      }),
      {
        status: 200,
        headers: { 'Content-Type': 'application/json' },
      }
    );
  };

  const result = await generateTextWithFallback({
    messages: [{ role: 'user', content: 'hi' }],
    retries: 1,
    timeoutMs: 500,
  });

  assert.equal(result.provider, 'openai');
  assert.equal(result.content, 'OK');
  assert.equal(calls, 2);
});

test('generateTextWithFallback does not retry non-transient auth failures', async () => {
  configureOpenAIProvider();

  let calls = 0;
  globalThis.fetch = async () => {
    calls += 1;
    return new Response('forbidden', { status: 401 });
  };

  await assert.rejects(
    generateTextWithFallback({
      messages: [{ role: 'user', content: 'hi' }],
      retries: 1,
      timeoutMs: 500,
    }),
    /HTTP 401/
  );

  assert.equal(calls, 1);
});
