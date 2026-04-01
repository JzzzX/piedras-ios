import assert from 'node:assert/strict';
import test from 'node:test';

import { buildBackendHealthPayload } from './backend-health.ts';

test('buildBackendHealthPayload stays unhealthy until startup bootstrap is ready', () => {
  const payload = buildBackendHealthPayload({
    mode: 'full',
    database: true,
    llmProviders: ['aihubmix'],
    asr: {
      ready: true,
      configured: true,
      reachable: true,
      missing: [],
      message: '豆包 ASR 代理在线',
      mode: 'doubao',
      provider: 'doubao-proxy',
      checkedAt: '2026-03-30T06:00:00.000Z',
      lastError: null,
    },
    audioFinalization: {
      configured: true,
      ready: true,
      ffmpegAvailable: true,
      storageReady: true,
      storagePersistent: true,
      storagePath: '/data/meetings',
      checkedAt: '2026-03-30T06:00:00.000Z',
      lastError: null,
      message: '音频补转写就绪',
    },
    llm: {
      configured: true,
      reachable: true,
      ready: true,
      checkedAt: '2026-03-30T06:00:00.000Z',
      lastError: null,
      provider: 'aihubmix',
      model: 'gemini-3-flash-preview',
      preset: 'aihubmix',
      message: 'AiHubMix 已配置',
    },
    startupBootstrap: {
      ready: false,
      status: 'failed',
      attempts: 2,
      startedAt: '2026-03-30T06:00:00.000Z',
      completedAt: '2026-03-30T06:00:01.000Z',
      lastError: 'database offline',
      schemaReady: false,
      missingItems: ['User 表'],
      legacyUsers: [],
      retryScheduled: true,
      retryAt: '2026-03-30T06:00:05.000Z',
    },
    checkedAt: '2026-03-30T06:00:02.000Z',
  });

  assert.equal(payload.ok, false);
  assert.equal(payload.recordingReady, false);
  assert.equal(payload.database, true);
  assert.equal(payload.startupBootstrap.ready, false);
});

test('buildBackendHealthPayload exposes startup bootstrap state in basic mode', () => {
  const payload = buildBackendHealthPayload({
    mode: 'basic',
    database: true,
    startupBootstrap: {
      ready: false,
      status: 'running',
      attempts: 1,
      startedAt: '2026-03-30T06:00:00.000Z',
      completedAt: null,
      lastError: null,
      schemaReady: false,
      missingItems: [],
      legacyUsers: [],
      retryScheduled: false,
      retryAt: null,
    },
    checkedAt: '2026-03-30T06:00:02.000Z',
  });

  assert.deepEqual(payload, {
    ok: false,
    database: true,
    startupBootstrap: {
      ready: false,
      status: 'running',
      attempts: 1,
      startedAt: '2026-03-30T06:00:00.000Z',
      completedAt: null,
      lastError: null,
      schemaReady: false,
      missingItems: [],
      legacyUsers: [],
      retryScheduled: false,
      retryAt: null,
    },
    checkedAt: '2026-03-30T06:00:02.000Z',
  });
});
