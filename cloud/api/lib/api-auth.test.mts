import assert from 'node:assert/strict';
import test from 'node:test';

import { resolveSupabaseUserContext } from './auth-context.ts';

test('resolveSupabaseUserContext reuses an existing user matched by authUserId', async () => {
  const ensureWorkspaceCalls: string[] = [];
  const fakeDb = {
    user: {
      findUnique: async ({ where }: any) => {
        if (where.authUserId === 'auth-user-1') {
          return {
            id: 'user-1',
            email: 'linked@example.com',
            authUserId: 'auth-user-1',
          };
        }
        return null;
      },
      findFirst: async () => null,
      update: async () => {
        throw new Error('should not update a user already linked by authUserId');
      },
      create: async () => {
        throw new Error('should not create a user already linked by authUserId');
      },
    },
  };

  const result = await resolveSupabaseUserContext(
    fakeDb as any,
    {
      authUserId: 'auth-user-1',
      email: 'linked@example.com',
      displayName: 'Linked User',
      sessionId: 'supabase-session-1',
      expiresAt: new Date('2026-03-27T12:00:00.000Z'),
    },
    async ({ userId }) => {
      ensureWorkspaceCalls.push(userId);
      return { id: 'workspace-1', name: '椰子面试' };
    }
  );

  assert.equal(result.user.id, 'user-1');
  assert.equal(result.user.email, 'linked@example.com');
  assert.equal(result.session.id, 'supabase-session-1');
  assert.deepEqual(ensureWorkspaceCalls, ['user-1']);
});

test('resolveSupabaseUserContext backfills authUserId onto a legacy user matched by email', async () => {
  const updates: Array<{ id: string; authUserId: string }> = [];
  const fakeDb = {
    user: {
      findUnique: async ({ where }: any) => {
        if (where.authUserId) {
          return null;
        }
        return null;
      },
      findFirst: async ({ where }: any) => {
        if (where.email === 'legacy@example.com') {
          return {
            id: 'user-legacy',
            email: 'legacy@example.com',
            authUserId: null,
            displayName: '',
          };
        }
        return null;
      },
      update: async ({ where, data }: any) => {
        updates.push({ id: where.id, authUserId: data.authUserId });
        return {
          id: where.id,
          email: 'legacy@example.com',
          authUserId: data.authUserId,
          displayName: '',
        };
      },
      create: async () => {
        throw new Error('should not create a user when email backfill succeeds');
      },
    },
  };

  const result = await resolveSupabaseUserContext(
    fakeDb as any,
    {
      authUserId: 'auth-user-legacy',
      email: 'legacy@example.com',
      displayName: nilIfBlank(''),
      sessionId: 'supabase-session-legacy',
      expiresAt: new Date('2026-03-27T12:00:00.000Z'),
    },
    async () => ({ id: 'workspace-legacy', name: 'Legacy Space' })
  );

  assert.equal(result.user.id, 'user-legacy');
  assert.deepEqual(updates, [{ id: 'user-legacy', authUserId: 'auth-user-legacy' }]);
  assert.equal(result.workspace.id, 'workspace-legacy');
});

test('resolveSupabaseUserContext creates a new user when no existing user matches', async () => {
  const createdUsers: string[] = [];
  const fakeDb = {
    user: {
      findUnique: async () => null,
      findFirst: async () => null,
      update: async () => {
        throw new Error('should not update when creating a new user');
      },
      create: async ({ data }: any) => {
        createdUsers.push(`${data.email}:${data.authUserId}:${data.displayName}`);
        return {
          id: 'user-created',
          email: data.email,
          authUserId: data.authUserId,
          displayName: data.displayName,
        };
      },
    },
  };

  const result = await resolveSupabaseUserContext(
    fakeDb as any,
    {
      authUserId: 'auth-user-new',
      email: 'new@example.com',
      displayName: 'New User',
      sessionId: 'supabase-session-new',
      expiresAt: new Date('2026-03-27T12:00:00.000Z'),
    },
    async () => ({ id: 'workspace-new', name: 'New Space' })
  );

  assert.equal(result.user.id, 'user-created');
  assert.deepEqual(createdUsers, ['new@example.com:auth-user-new:New User']);
  assert.equal(result.workspace.name, 'New Space');
});

function nilIfBlank(value: string) {
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : null;
}
