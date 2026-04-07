const assert = require('node:assert/strict');
const test = require('node:test');

const {
  buildLegacyBootstrapPlans,
  mergeSchemaStatuses,
  summarizeAuthSchemaStatus,
  summarizeMediaSyncSchemaStatus,
} = require('./auth-startup-bootstrap.cjs');

test('summarizeAuthSchemaStatus reports missing auth tables and workspace owner column', () => {
  const status = summarizeAuthSchemaStatus({
    tableNames: ['InviteCode'],
    workspaceOwnerColumnPresent: false,
    userAuthUserIdColumnPresent: false,
    userAuthUserIdUniqueIndexPresent: false,
    userPasswordHashNullable: false,
  });

  assert.equal(status.ready, false);
  assert.deepEqual(status.missingItems, [
    'User 表',
    'AuthSession 表',
    'Workspace.ownerUserId 字段',
    'User.authUserId 字段',
    'User.authUserId 唯一索引',
    'User.passwordHash 可空约束',
  ]);
});

test('summarizeAuthSchemaStatus reports missing user auth schema even when core tables exist', () => {
  const status = summarizeAuthSchemaStatus({
    tableNames: ['User', 'AuthSession', 'InviteCode'],
    workspaceOwnerColumnPresent: true,
    userAuthUserIdColumnPresent: false,
    userAuthUserIdUniqueIndexPresent: false,
    userPasswordHashNullable: false,
    meetingAudioEnhancedColumnsPresent: false,
  });

  assert.equal(status.ready, false);
  assert.deepEqual(status.missingItems, [
    'User.authUserId 字段',
    'User.authUserId 唯一索引',
    'User.passwordHash 可空约束',
    'Meeting 音频 AI 笔记字段',
  ]);
});

test('summarizeAuthSchemaStatus reports missing meeting audio ai columns', () => {
  const status = summarizeAuthSchemaStatus({
    tableNames: ['User', 'AuthSession', 'InviteCode'],
    workspaceOwnerColumnPresent: true,
    userAuthUserIdColumnPresent: true,
    userAuthUserIdUniqueIndexPresent: true,
    userPasswordHashNullable: true,
    meetingAudioEnhancedColumnsPresent: false,
  });

  assert.equal(status.ready, false);
  assert.deepEqual(status.missingItems, ['Meeting 音频 AI 笔记字段']);
});

test('summarizeMediaSyncSchemaStatus reports missing meeting media sync schema objects', () => {
  const status = summarizeMediaSyncSchemaStatus({
    meetingAudioCloudSyncEnabledColumnPresent: false,
    meetingPreviousCollectionIdColumnPresent: false,
    meetingDeletedAtColumnPresent: false,
    meetingAttachmentTablePresent: false,
    meetingAttachmentIndexPresent: false,
    meetingAttachmentForeignKeyPresent: false,
  });

  assert.equal(status.ready, false);
  assert.deepEqual(status.missingItems, [
    'Meeting.audioCloudSyncEnabled 字段',
    'Meeting.previousCollectionId 字段',
    'Meeting.deletedAt 字段',
    'MeetingAttachment 表',
    'MeetingAttachment_meetingId_updatedAt_idx 索引',
    'MeetingAttachment_meetingId_fkey 外键',
  ]);
});

test('mergeSchemaStatuses keeps bootstrap unhealthy until both auth and media sync schema are ready', () => {
  const merged = mergeSchemaStatuses(
    {
      ready: true,
      missingItems: [],
    },
    {
      ready: false,
      missingItems: ['MeetingAttachment 表'],
    }
  );

  assert.equal(merged.ready, false);
  assert.deepEqual(merged.missingItems, ['MeetingAttachment 表']);
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
