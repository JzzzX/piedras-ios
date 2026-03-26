import assert from 'node:assert/strict';
import test from 'node:test';

import {
  AdminManagementError,
  assignLegacyWorkspaceToUser,
  createManagedUser,
  resetManagedUserPassword,
} from './admin-management.ts';

test('createManagedUser claims the requested legacy workspace instead of creating a new one', async () => {
  const calls: string[] = [];
  const fakeDb = {
    $queryRawUnsafe: async (query: string) => {
      if (query.includes('information_schema.tables')) {
        return [
          { objectName: 'User' },
          { objectName: 'AuthSession' },
          { objectName: 'InviteCode' },
        ];
      }
      return [{ objectName: 'ownerUserId' }];
    },
    user: {
      findUnique: async () => null,
    },
    $transaction: async (callback: (tx: any) => Promise<any>) =>
      callback({
        user: {
          create: async ({ data }: any) => {
            calls.push(`create-user:${data.email}`);
            return {
              id: 'user-1',
              email: data.email,
              displayName: data.displayName,
            };
          },
        },
        workspace: {
          findFirst: async ({ where }: any) => {
            if (where.ownerUserId === 'user-1') {
              return null;
            }
            return {
              id: 'legacy-workspace-1',
              ownerUserId: null,
            };
          },
          update: async ({ where, data }: any) => {
            calls.push(`claim-workspace:${where.id}:${data.ownerUserId}`);
            return {
              id: where.id,
              ownerUserId: data.ownerUserId,
            };
          },
        },
      }),
  };

  const created = await createManagedUser(fakeDb as any, {
    email: ' Legacy@Example.com ',
    password: 'password-123',
    displayName: 'Legacy User',
    legacyWorkspaceId: 'legacy-workspace-1',
  });

  assert.equal(created.user.email, 'legacy@example.com');
  assert.equal(created.workspace.id, 'legacy-workspace-1');
  assert.deepEqual(calls, [
    'create-user:legacy@example.com',
    'claim-workspace:legacy-workspace-1:user-1',
  ]);
});

test('assignLegacyWorkspaceToUser rejects users that already own a workspace', async () => {
  const fakeDb = {
    $queryRawUnsafe: async (query: string) => {
      if (query.includes('information_schema.tables')) {
        return [
          { objectName: 'User' },
          { objectName: 'AuthSession' },
          { objectName: 'InviteCode' },
        ];
      }
      return [{ objectName: 'ownerUserId' }];
    },
    user: {
      findUnique: async () => ({
        id: 'user-1',
        email: 'existing@example.com',
      }),
    },
    workspace: {
      findFirst: async ({ where }: any) => {
        if (where.id) {
          return {
            id: 'legacy-workspace-1',
            ownerUserId: null,
            name: 'Legacy Space',
          };
        }
        if (where.ownerUserId === 'user-1') {
          return {
            id: 'owned-workspace',
            ownerUserId: 'user-1',
            name: 'Owned Space',
          };
        }
        return null;
      },
      update: async () => {
        throw new Error('should not update when target user already owns a workspace');
      },
    },
  };

  await assert.rejects(
    assignLegacyWorkspaceToUser(fakeDb as any, {
      workspaceId: 'legacy-workspace-1',
      userId: 'user-1',
    }),
    (error: unknown) =>
      error instanceof AdminManagementError &&
      error.status === 409 &&
      error.message === '目标账号已有工作区，不能再接管 legacy 数据'
  );
});

test('resetManagedUserPassword stores a new verifiable hash', async () => {
  let updatedPasswordHash = '';
  const fakeDb = {
    $queryRawUnsafe: async (query: string) => {
      if (query.includes('information_schema.tables')) {
        return [
          { objectName: 'User' },
          { objectName: 'AuthSession' },
          { objectName: 'InviteCode' },
        ];
      }
      return [{ objectName: 'ownerUserId' }];
    },
    user: {
      update: async ({ data }: any) => {
        updatedPasswordHash = data.passwordHash;
        return {
          id: 'user-1',
          email: 'reset@example.com',
        };
      },
    },
  };

  const result = await resetManagedUserPassword(fakeDb as any, {
    userId: 'user-1',
    password: 'new-password-123',
  });

  assert.equal(result.email, 'reset@example.com');
  assert.match(updatedPasswordHash, /^scrypt\$/);
});
