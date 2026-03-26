const assert = require('node:assert/strict');
const test = require('node:test');

const {
  buildLegacyBootstrapPlans,
  summarizeAuthSchemaStatus,
} = require('./auth-startup-bootstrap.cjs');

test('summarizeAuthSchemaStatus reports missing auth tables and workspace owner column', () => {
  const status = summarizeAuthSchemaStatus({
    tableNames: ['InviteCode'],
    workspaceOwnerColumnPresent: false,
  });

  assert.equal(status.ready, false);
  assert.deepEqual(status.missingItems, [
    'User 表',
    'AuthSession 表',
    'Workspace.ownerUserId 字段',
  ]);
});

test('buildLegacyBootstrapPlans assigns the two largest legacy workspaces to fixed bootstrap accounts', () => {
  const plans = buildLegacyBootstrapPlans([
    { id: 'workspace-small', name: 'Small', meetingCount: 3 },
    { id: 'workspace-main', name: 'Main', meetingCount: 24 },
    { id: 'workspace-archive', name: 'Archive', meetingCount: 10 },
  ]);

  assert.deepEqual(plans, [
    {
      email: 'legacy-main@piedras.local',
      displayName: '历史主数据',
      workspaceId: 'workspace-main',
      workspaceName: 'Main',
    },
    {
      email: 'legacy-archive@piedras.local',
      displayName: '历史归档数据',
      workspaceId: 'workspace-archive',
      workspaceName: 'Archive',
    },
  ]);
});
