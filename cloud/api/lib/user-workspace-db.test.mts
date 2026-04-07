import assert from 'node:assert/strict';
import test from 'node:test';

import { createWorkspaceForUser } from './user-workspace-db.ts';

test('createWorkspaceForUser appends a new workspace instead of rejecting users with an existing default workspace', async () => {
  let createdData: Record<string, unknown> | null = null;
  const fakeDb = {
    workspace: {
      findFirst: async () => ({ sortOrder: 2 }),
      create: async ({ data }: { data: Record<string, unknown> }) => {
        createdData = data;
        return {
          id: 'workspace-3',
          ...data,
        };
      },
    },
  };

  const workspace = await createWorkspaceForUser(fakeDb as any, {
    userId: 'user-1',
    name: '项目 A',
    description: '项目文件夹',
    icon: 'folder',
    color: '#123456',
    workflowMode: 'general',
    modeLabel: '',
  });

  assert.equal(workspace.id, 'workspace-3');
  assert.equal(workspace.name, '项目 A');
  assert.equal(createdData?.ownerUserId, 'user-1');
  assert.equal(createdData?.sortOrder, 3);
});
