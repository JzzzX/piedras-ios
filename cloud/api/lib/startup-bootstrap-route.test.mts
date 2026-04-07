import assert from 'node:assert/strict';
import test from 'node:test';

import { runWithStartupBootstrapGuard } from './startup-bootstrap-route.ts';

test('runWithStartupBootstrapGuard returns the startup guard response and skips the handler when bootstrap is not ready', async () => {
  let didRunHandler = false;

  const response = await runWithStartupBootstrapGuard(
    {
      requestId: 'req-collections',
      route: '/api/collections',
    },
    async () => {
      didRunHandler = true;
      return Response.json({ ok: true });
    },
    {
      ready: false,
      status: 'failed',
      schemaReady: false,
      missingItems: ['Meeting.deletedAt 字段'],
    }
  );

  assert.equal(didRunHandler, false);
  assert.equal(response.status, 503);
  const payload = await response.json();
  assert.equal(payload.route, '/api/collections');
  assert.match(payload.error, /Meeting\.deletedAt 字段/);
});

test('runWithStartupBootstrapGuard runs the handler when bootstrap is ready', async () => {
  let didRunHandler = false;

  const response = await runWithStartupBootstrapGuard(
    {
      requestId: 'req-collections-ready',
      route: '/api/collections',
    },
    async () => {
      didRunHandler = true;
      return Response.json({ ok: true }, { status: 201 });
    },
    {
      ready: true,
      status: 'ready',
      schemaReady: true,
      missingItems: [],
    }
  );

  assert.equal(didRunHandler, true);
  assert.equal(response.status, 201);
  assert.deepEqual(await response.json(), { ok: true });
});
