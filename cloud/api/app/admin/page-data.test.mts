import assert from 'node:assert/strict';
import test from 'node:test';

import { loadAdminDashboardState } from './page-data.ts';

test('loadAdminDashboardState skips dashboard loading for anonymous admin sessions', async () => {
  let called = false;

  const result = await loadAdminDashboardState(
    {
      authenticated: false,
    },
    async () => {
      called = true;
      return { schema: { ready: true }, users: [] };
    }
  );

  assert.equal(called, false);
  assert.equal(result.dashboard, null);
  assert.equal(result.dashboardError, '');
});

test('loadAdminDashboardState converts dashboard loader failures into an inline admin error', async () => {
  const result = await loadAdminDashboardState(
    {
      authenticated: true,
    },
    async () => {
      throw new Error('database exploded');
    }
  );

  assert.equal(result.dashboard, null);
  assert.equal(result.dashboardError, '后台数据加载失败，请稍后重试');
});
