import assert from 'node:assert/strict';
import test from 'node:test';

import {
  interpretDoubaoProxyHealth,
  isIgnorableDoubaoSessionTimeout,
  resolveAsrProxyHealthPath,
} from './asr.ts';

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

test('isIgnorableDoubaoSessionTimeout matches historical session timeout errors', () => {
  assert.equal(
    isIgnorableDoubaoSessionTimeout(
      '豆包 ASR 错误 55000000: [Server-side generic error] read result timeout'
    ),
    true
  );
  assert.equal(isIgnorableDoubaoSessionTimeout('豆包 ASR 初始化失败：invalid token'), false);
});

test('interpretDoubaoProxyHealth keeps legacy proxy timeout payload ready when recent success exists', () => {
  const interpreted = interpretDoubaoProxyHealth({
    ok: true,
    lastError: '豆包 ASR 错误 55000000: [Server-side generic error] read result timeout',
    lastCloseReason: '豆包 ASR 错误 55000000: [Server-side generic error] read result timeout',
    lastReadyAt: '2026-04-09T03:08:53.836Z',
    lastFinalAt: '2026-04-09T03:17:49.402Z',
    lastPartialAt: '2026-04-09T03:17:55.975Z',
    lastUpstreamCloseAt: '2026-04-09T03:17:58.144Z',
    lastCloseAt: '2026-04-09T03:17:58.093Z',
  });

  assert.deepEqual(interpreted, {
    ready: true,
    lastError: null,
    recentTimeoutDetail: '豆包 ASR 错误 55000000: [Server-side generic error] read result timeout',
  });
});

test('interpretDoubaoProxyHealth keeps initialization failures blocking', () => {
  const interpreted = interpretDoubaoProxyHealth({
    ok: true,
    lastError: '豆包 ASR 初始化失败：invalid token',
    lastCloseReason: '豆包 ASR 初始化失败：invalid token',
    lastCloseAt: '2026-04-09T03:18:00.000Z',
  });

  assert.deepEqual(interpreted, {
    ready: false,
    lastError: '豆包 ASR 初始化失败：invalid token',
    recentTimeoutDetail: null,
  });
});

test('interpretDoubaoProxyHealth does not treat timeout-only payload as ready without any success signal', () => {
  const interpreted = interpretDoubaoProxyHealth({
    ok: true,
    lastError: '豆包 ASR 错误 55000000: [Server-side generic error] read result timeout',
    lastCloseReason: '豆包 ASR 错误 55000000: [Server-side generic error] read result timeout',
    lastCloseAt: '2026-04-09T03:18:00.000Z',
  });

  assert.deepEqual(interpreted, {
    ready: false,
    lastError: '豆包 ASR 错误 55000000: [Server-side generic error] read result timeout',
    recentTimeoutDetail: null,
  });
});
