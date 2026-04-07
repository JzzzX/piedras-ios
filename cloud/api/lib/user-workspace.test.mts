import assert from 'node:assert/strict';
import test from 'node:test';

import { resolveUserWorkspaceId } from './user-workspace.ts';

test('resolveUserWorkspaceId always prefers the authenticated users default workspace', () => {
  assert.equal(
    resolveUserWorkspaceId({
      defaultWorkspaceId: 'workspace-user-a',
      requestedWorkspaceId: 'workspace-user-b',
    }),
    'workspace-user-a'
  );
});

test('resolveUserWorkspaceId falls back to the authenticated users default workspace when request omits one', () => {
  assert.equal(
    resolveUserWorkspaceId({
      defaultWorkspaceId: 'workspace-user-a',
      requestedWorkspaceId: undefined,
    }),
    'workspace-user-a'
  );
});

test('resolveUserWorkspaceId allows an explicitly selected workspace when it belongs to the user', () => {
  assert.equal(
    resolveUserWorkspaceId({
      defaultWorkspaceId: 'workspace-user-a',
      requestedWorkspaceId: 'workspace-user-b',
      accessibleWorkspaceIds: ['workspace-user-b'],
    }),
    'workspace-user-b'
  );
});

test('resolveUserWorkspaceId falls back to the default workspace when the requested workspace is not accessible', () => {
  assert.equal(
    resolveUserWorkspaceId({
      defaultWorkspaceId: 'workspace-user-a',
      requestedWorkspaceId: 'workspace-user-b',
      accessibleWorkspaceIds: [],
    }),
    'workspace-user-a'
  );
});
