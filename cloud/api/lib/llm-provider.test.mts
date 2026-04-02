import assert from 'node:assert/strict';
import test from 'node:test';

import llmProviderModule from './llm-provider.ts';

const {
  generateTextWithFallback,
  getConfiguredProviders,
  hasAvailableLlm,
  probeConfiguredLlm,
  resolveLlmRequestPolicy,
} = llmProviderModule as typeof import('./llm-provider.ts');

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

function configureAiHubMixProvider() {
  process.env.LLM_PROVIDER = 'aihubmix';
  process.env.AIHUBMIX_API_KEY = 'test-key';
  process.env.AIHUBMIX_MODEL = 'gemini-3-flash-preview';
  process.env.AIHUBMIX_BASE_URL = 'https://example.com/v1';
  process.env.AIHUBMIX_PATH = '/chat/completions';
}

test.afterEach(() => {
  resetEnv();
  globalThis.fetch = ORIGINAL_FETCH;
});

test('generateTextWithFallback retries transient AiHubMix failures once', async () => {
  configureAiHubMixProvider();

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

  assert.equal(result.provider, 'aihubmix');
  assert.equal(result.content, 'OK');
  assert.equal(calls, 2);
});

test('generateTextWithFallback does not retry non-transient auth failures', async () => {
  configureAiHubMixProvider();

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

test('generateTextWithFallback respects per-request retry override', async () => {
  configureAiHubMixProvider();
  process.env.LLM_TIMEOUT_MS = '10';
  process.env.LLM_RETRIES = '1';

  let attempts = 0;
  globalThis.fetch = (async () => {
    attempts += 1;
    return await new Promise<Response>(() => {});
  }) as typeof fetch;

  await assert.rejects(
    generateTextWithFallback({
      messages: [{ role: 'user', content: '请回复 OK' }],
      timeoutMs: 10,
      retries: 0,
    }),
    /请求超时/
  );

  assert.equal(attempts, 1);
});

test('generateTextWithFallback sends audio content to AiHubMix payloads', async () => {
  configureAiHubMixProvider();

  let requestBody: Record<string, unknown> | null = null;
  globalThis.fetch = async (_input, init) => {
    requestBody = JSON.parse(String(init?.body || '{}')) as Record<string, unknown>;
    return new Response(
      JSON.stringify({
        choices: [{ message: { content: '音频总结完成' } }],
      }),
      {
        status: 200,
        headers: { 'Content-Type': 'application/json' },
      }
    );
  };

  const result = await generateTextWithFallback({
    messages: [
      {
        role: 'user',
        content: [
          { type: 'text', text: '请总结这段会议音频' },
          { type: 'audio', mimeType: 'audio/mpeg', data: 'ZmFrZS1hdWRpbw==' },
        ],
      },
    ],
    timeoutMs: 500,
  });

  assert.equal(result.content, '音频总结完成');
  const messages = (requestBody?.messages || []) as Array<Record<string, unknown>>;
  const content = (messages[0]?.content || []) as Array<Record<string, unknown>>;
  assert.equal(content[0]?.type, 'text');
  assert.equal(content[1]?.type, 'input_audio');
  assert.deepEqual(content[1]?.input_audio, {
    data: 'ZmFrZS1hdWRpbw==',
    format: 'mp3',
  });
});

test('probeConfiguredLlm rejects placeholder text responses from AiHubMix', async () => {
  configureAiHubMixProvider();

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

  await assert.rejects(probeConfiguredLlm(500), /返回了不可用正文/);
});

test('getConfiguredProviders ignores legacy OPENAI env vars', () => {
  process.env.LLM_PROVIDER = 'aihubmix';
  process.env.OPENAI_API_KEY = 'legacy-key';
  process.env.OPENAI_MODEL = 'legacy-model';
  process.env.OPENAI_BASE_URL = 'https://legacy.example.com/v1';
  process.env.OPENAI_PATH = '/chat/completions';

  assert.deepEqual(getConfiguredProviders(), []);
  assert.equal(hasAvailableLlm(), false);
});

test('resolveLlmRequestPolicy prefers per-scenario timeout and retry env vars', () => {
  process.env.LLM_TIMEOUT_MS = '12000';
  process.env.LLM_RETRIES = '1';
  process.env.LLM_CHAT_TIMEOUT_MS = '30000';
  process.env.LLM_CHAT_RETRIES = '2';

  assert.deepEqual(resolveLlmRequestPolicy('chat'), {
    timeoutMs: 30000,
    retries: 2,
  });
  assert.deepEqual(resolveLlmRequestPolicy('enhance'), {
    timeoutMs: 12000,
    retries: 1,
  });
});
