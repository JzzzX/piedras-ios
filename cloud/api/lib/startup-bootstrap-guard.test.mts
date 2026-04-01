import assert from 'node:assert/strict';
import test from 'node:test';

import { requireStartupBootstrapReady } from './startup-bootstrap-guard.ts';

test('requireStartupBootstrapReady returns null when bootstrap is ready', async () => {
  const response = requireStartupBootstrapReady(
    {
      requestId: 'req-ready',
      route: '/api/meetings',
    },
    {
      ready: true,
      status: 'ready',
      attempts: 1,
      startedAt: null,
      completedAt: null,
      lastError: null,
      schemaReady: true,
      missingItems: [],
      legacyUsers: [],
      retryScheduled: false,
      retryAt: null,
    }
  );

  assert.equal(response, null);
});

test('requireStartupBootstrapReady returns a 503 response with missing schema items when bootstrap is not ready', async () => {
  const response = requireStartupBootstrapReady(
    {
      requestId: 'req-bootstrap',
      route: '/api/meetings/[id]',
    },
    {
      ready: false,
      status: 'failed',
      attempts: 2,
      startedAt: null,
      completedAt: null,
      lastError: 'schema drift',
      schemaReady: false,
      missingItems: ['Meeting.audioCloudSyncEnabled 字段', 'MeetingAttachment 表'],
      legacyUsers: [],
      retryScheduled: true,
      retryAt: '2026-04-01T20:00:00.000Z',
    }
  );

  assert.ok(response instanceof Response);
  assert.equal(response.status, 503);

  const payload = await response.json();
  assert.equal(payload.requestId, 'req-bootstrap');
  assert.equal(payload.route, '/api/meetings/[id]');
  assert.match(payload.error, /Meeting\.audioCloudSyncEnabled 字段/);
  assert.match(payload.error, /MeetingAttachment 表/);
});
