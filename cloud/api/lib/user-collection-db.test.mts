import assert from 'node:assert/strict';
import test from 'node:test';

import {
  createCollectionForWorkspace,
  deleteCollectionForWorkspace,
  ensureDefaultCollectionForWorkspace,
  ensureWorkspaceCollectionsHydrated,
  ensureRecentlyDeletedCollectionForWorkspace,
  serializeCollection,
} from './user-collection-db.ts';

test('ensureDefaultCollectionForWorkspace creates the default Default Folder collection when missing', async () => {
  const calls: string[] = [];
  const fakeDb = {
    collection: {
      findFirst: async ({ where }: any) => {
        calls.push(`findFirst:${JSON.stringify(where)}`);
        return null;
      },
      create: async ({ data }: any) => {
        calls.push(`create:${data.workspaceId}:${data.name}:${data.sortOrder}`);
        return {
          id: 'collection-notes',
          workspaceId: data.workspaceId,
          name: data.name,
          description: data.description,
          icon: data.icon,
          color: data.color,
          handoffSummary: '',
          candidateStatus: 'new',
          nextInterviewer: '',
          nextFocus: '',
          sortOrder: data.sortOrder,
        };
      },
      findMany: async () => [],
    },
  };

  const collection = await ensureDefaultCollectionForWorkspace(fakeDb as any, {
    workspaceId: 'workspace-1',
  });

  assert.equal(collection.id, 'collection-notes');
  assert.equal(collection.name, 'Default Folder');
  assert.ok(calls.some((entry) => entry.startsWith('create:workspace-1:Default Folder:0')));
});

test('ensureWorkspaceCollectionsHydrated backfills legacy ungrouped meetings into the default collection', async () => {
  const calls: string[] = [];
  const fakeDb = {
    collection: {
      findFirst: async ({ where }: any) => {
        if (where.description === 'Piedras default notes collection') {
          return {
            id: 'collection-notes',
            workspaceId: 'workspace-1',
            name: 'Default Folder',
            description: 'Piedras default notes collection',
            icon: 'tray.full',
            color: '#0f766e',
            handoffSummary: '',
            candidateStatus: 'new',
            nextInterviewer: '',
            nextFocus: '',
            sortOrder: 0,
          };
        }

        if (where.description === 'Piedras recently deleted notes collection') {
          return {
            id: 'collection-recently-deleted',
            workspaceId: 'workspace-1',
            name: 'Recently Deleted',
            description: 'Piedras recently deleted notes collection',
            icon: 'trash',
            color: '#9f1239',
            handoffSummary: '',
            candidateStatus: 'new',
            nextInterviewer: '',
            nextFocus: '',
            sortOrder: 999,
          };
        }

        return null;
      },
      findMany: async ({ where }: any) => {
        calls.push(`findMany:${where.workspaceId}`);
        return [
          {
            id: 'collection-notes',
            workspaceId: 'workspace-1',
            name: 'Default Folder',
            description: 'Piedras default notes collection',
            icon: 'tray.full',
            color: '#0f766e',
            handoffSummary: '',
            candidateStatus: 'new',
            nextInterviewer: '',
            nextFocus: '',
            sortOrder: 0,
          },
          {
            id: 'collection-projects',
            workspaceId: 'workspace-1',
            name: 'Projects',
            description: '',
            icon: 'folder',
            color: '#94a3b8',
            handoffSummary: '',
            candidateStatus: 'new',
            nextInterviewer: '',
            nextFocus: '',
            sortOrder: 1,
          },
          {
            id: 'collection-recently-deleted',
            workspaceId: 'workspace-1',
            name: 'Recently Deleted',
            description: 'Piedras recently deleted notes collection',
            icon: 'trash',
            color: '#9f1239',
            handoffSummary: '',
            candidateStatus: 'new',
            nextInterviewer: '',
            nextFocus: '',
            sortOrder: 999,
          },
        ];
      },
    },
    meeting: {
      updateMany: async ({ where, data }: any) => {
        calls.push(`updateMany:${where.workspaceId}:${data.collectionId}`);
        return { count: 3 };
      },
    },
  };

  const result = await ensureWorkspaceCollectionsHydrated(fakeDb as any, {
    workspaceId: 'workspace-1',
  });

  assert.equal(result.defaultCollection.id, 'collection-notes');
  assert.equal(result.recentlyDeletedCollection.id, 'collection-recently-deleted');
  assert.equal(result.collections.length, 3);
  assert.ok(calls.includes('updateMany:workspace-1:collection-notes'));
});

test('ensureDefaultCollectionForWorkspace reuses and normalizes a legacy Notes default collection', async () => {
  const calls: string[] = [];
  const fakeDb = {
    collection: {
      findFirst: async () => ({
        id: 'collection-notes',
        workspaceId: 'workspace-1',
        name: 'Notes',
        description: 'Piedras default notes collection',
        icon: 'tray.full',
        color: '#0f766e',
        handoffSummary: '',
        candidateStatus: 'new',
        nextInterviewer: '',
        nextFocus: '',
        sortOrder: 0,
      }),
      update: async ({ where, data }: any) => {
        calls.push(`update:${where.id}:${data.name}`);
        return {
          id: where.id,
          workspaceId: 'workspace-1',
          name: data.name,
          description: data.description,
          icon: data.icon,
          color: data.color,
          handoffSummary: '',
          candidateStatus: 'new',
          nextInterviewer: '',
          nextFocus: '',
          sortOrder: data.sortOrder,
        };
      },
      create: async () => {
        throw new Error('should not create a second default collection');
      },
    },
  };

  const collection = await ensureDefaultCollectionForWorkspace(fakeDb as any, {
    workspaceId: 'workspace-1',
  });

  assert.equal(collection.id, 'collection-notes');
  assert.equal(collection.name, 'Default Folder');
  assert.ok(calls.includes('update:collection-notes:Default Folder'));
});

test('createCollectionForWorkspace appends after the existing collections for the same workspace', async () => {
  const fakeDb = {
    collection: {
      findFirst: async ({ where }: any) => {
        assert.equal(where.workspaceId, 'workspace-1');
        return { sortOrder: 4 };
      },
      create: async ({ data }: any) => ({
        id: 'collection-5',
        workspaceId: data.workspaceId,
        name: data.name,
        description: data.description,
        icon: data.icon,
        color: data.color,
        handoffSummary: '',
        candidateStatus: 'new',
        nextInterviewer: '',
        nextFocus: '',
        sortOrder: data.sortOrder,
      }),
    },
  };

  const created = await createCollectionForWorkspace(fakeDb as any, {
    workspaceId: 'workspace-1',
    name: '  Design  ',
  });

  assert.equal(created.name, 'Design');
  assert.equal(created.sortOrder, 5);
});

test('ensureRecentlyDeletedCollectionForWorkspace creates the system trash collection when missing', async () => {
  const calls: string[] = [];
  const fakeDb = {
    collection: {
      findFirst: async ({ where }: any) => {
        calls.push(`findFirst:${JSON.stringify(where)}`);
        return null;
      },
      create: async ({ data }: any) => {
        calls.push(`create:${data.workspaceId}:${data.name}:${data.sortOrder}`);
        return {
          id: 'collection-recently-deleted',
          workspaceId: data.workspaceId,
          name: data.name,
          description: data.description,
          icon: data.icon,
          color: data.color,
          handoffSummary: '',
          candidateStatus: 'new',
          nextInterviewer: '',
          nextFocus: '',
          sortOrder: data.sortOrder,
        };
      },
    },
  };

  const collection = await ensureRecentlyDeletedCollectionForWorkspace(fakeDb as any, {
    workspaceId: 'workspace-1',
  });

  assert.equal(collection.id, 'collection-recently-deleted');
  assert.equal(collection.name, 'Recently Deleted');
  assert.ok(calls.some((entry) => entry.startsWith('create:workspace-1:Recently Deleted:')));
});

test('serializeCollection marks the default collection explicitly', () => {
  const payload = serializeCollection(
    {
      id: 'collection-notes',
      workspaceId: 'workspace-1',
      name: 'Default Folder',
      description: 'Piedras default notes collection',
      icon: 'tray.full',
      color: '#0f766e',
      handoffSummary: '',
      candidateStatus: 'new',
      nextInterviewer: '',
      nextFocus: '',
      sortOrder: 0,
    } as any,
    'collection-notes',
    'collection-recently-deleted'
  );

  assert.deepEqual(payload, {
    id: 'collection-notes',
    name: 'Default Folder',
    isDefault: true,
    isRecentlyDeleted: false,
  });
});

test('serializeCollection marks the recently deleted collection explicitly', () => {
  const payload = serializeCollection(
    {
      id: 'collection-recently-deleted',
      workspaceId: 'workspace-1',
      name: 'Recently Deleted',
      description: 'Piedras recently deleted notes collection',
      icon: 'trash',
      color: '#9f1239',
      handoffSummary: '',
      candidateStatus: 'new',
      nextInterviewer: '',
      nextFocus: '',
      sortOrder: 999,
    } as any,
    'collection-notes',
    'collection-recently-deleted'
  );

  assert.deepEqual(payload, {
    id: 'collection-recently-deleted',
    name: 'Recently Deleted',
    isDefault: false,
    isRecentlyDeleted: true,
  });
});

test('deleteCollectionForWorkspace reassigns dependent records before deleting a regular collection', async () => {
  const calls: string[] = [];
  const fakeDb = {
    collection: {
      findFirst: async ({ where }: any) => {
        if (where.workspaceId === 'workspace-1' && where.description === 'Piedras default notes collection') {
          return {
            id: 'collection-notes',
            workspaceId: 'workspace-1',
            name: 'Default Folder',
            description: 'Piedras default notes collection',
            icon: 'tray.full',
            color: '#0f766e',
            handoffSummary: '',
            candidateStatus: 'new',
            nextInterviewer: '',
            nextFocus: '',
            sortOrder: 0,
          };
        }
        if (where.workspaceId === 'workspace-1' && where.description === 'Piedras recently deleted notes collection') {
          return {
            id: 'collection-recently-deleted',
            workspaceId: 'workspace-1',
            name: 'Recently Deleted',
            description: 'Piedras recently deleted notes collection',
            icon: 'trash',
            color: '#9f1239',
            handoffSummary: '',
            candidateStatus: 'new',
            nextInterviewer: '',
            nextFocus: '',
            sortOrder: 999,
          };
        }
        return null;
      },
      findUnique: async ({ where }: any) => ({
        id: where.id,
        workspaceId: 'workspace-1',
        name: 'Projects',
        description: '',
        icon: 'folder',
        color: '#94a3b8',
        handoffSummary: '',
        candidateStatus: 'new',
        nextInterviewer: '',
        nextFocus: '',
        sortOrder: 1,
      }),
      delete: async ({ where }: any) => {
        calls.push(`collection.delete:${where.id}`);
        return { id: where.id };
      },
    },
    meeting: {
      updateMany: async ({ where, data }: any) => {
        calls.push(`meeting.updateMany:${JSON.stringify(where)}:${JSON.stringify(data)}`);
        return { count: where.deletedAt === null ? 2 : 1 };
      },
    },
    workspaceAsset: {
      updateMany: async ({ where, data }: any) => {
        calls.push(`asset.updateMany:${JSON.stringify(where)}:${JSON.stringify(data)}`);
        return { count: 3 };
      },
    },
  };

  const result = await deleteCollectionForWorkspace(fakeDb as any, {
    workspaceId: 'workspace-1',
    collectionId: 'collection-projects',
  });

  assert.deepEqual(result, {
    deletedCollectionId: 'collection-projects',
    reassignedMeetingCount: 2,
    reassignedWorkspaceAssetCount: 3,
    repairedPreviousCollectionCount: 1,
  });
  assert.ok(calls.some((entry) => entry.includes('"collectionId":"collection-projects","deletedAt":null')));
  assert.ok(calls.some((entry) => entry.includes('"previousCollectionId":"collection-projects","deletedAt":{"not":null}')));
  assert.ok(calls.includes('collection.delete:collection-projects'));
});

test('deleteCollectionForWorkspace rejects system collections', async () => {
  const fakeDb = {
    collection: {
      findFirst: async ({ where }: any) => {
        if (where.description === 'Piedras default notes collection') {
          return {
            id: 'collection-notes',
            workspaceId: 'workspace-1',
            name: 'Default Folder',
            description: 'Piedras default notes collection',
            icon: 'tray.full',
            color: '#0f766e',
            handoffSummary: '',
            candidateStatus: 'new',
            nextInterviewer: '',
            nextFocus: '',
            sortOrder: 0,
          };
        }
        if (where.description === 'Piedras recently deleted notes collection') {
          return {
            id: 'collection-recently-deleted',
            workspaceId: 'workspace-1',
            name: 'Recently Deleted',
            description: 'Piedras recently deleted notes collection',
            icon: 'trash',
            color: '#9f1239',
            handoffSummary: '',
            candidateStatus: 'new',
            nextInterviewer: '',
            nextFocus: '',
            sortOrder: 999,
          };
        }
        return null;
      },
      findUnique: async ({ where }: any) => ({
        id: where.id,
        workspaceId: 'workspace-1',
      }),
    },
  };

  await assert.rejects(
    () =>
      deleteCollectionForWorkspace(fakeDb as any, {
        workspaceId: 'workspace-1',
        collectionId: 'collection-notes',
      }),
    /system collection/i
  );
});
