import assert from 'node:assert/strict';
import test from 'node:test';

import { identityFromSupabaseClaims, verifySupabaseAccessToken } from './supabase-auth.ts';

test('identityFromSupabaseClaims maps verified claims into an auth identity', () => {
  const result = identityFromSupabaseClaims({
    sub: 'auth-user-1',
    email: 'Test.User@example.com',
    exp: 1_900_000_000,
    session_id: 'session-1',
    user_metadata: {
      display_name: 'Test User',
    },
  });

  assert.deepEqual(result, {
    authUserId: 'auth-user-1',
    email: 'test.user@example.com',
    displayName: 'Test User',
    sessionId: 'session-1',
    expiresAt: new Date(1_900_000_000 * 1000),
  });
});

test('identityFromSupabaseClaims returns null when required claims are missing', () => {
  assert.equal(identityFromSupabaseClaims({ email: 'missing-sub@example.com' }), null);
  assert.equal(identityFromSupabaseClaims({ sub: 'auth-user-2' }), null);
  assert.equal(
    identityFromSupabaseClaims({
      sub: 'auth-user-3',
      email: 'missing-exp@example.com',
    }),
    null
  );
});

test('verifySupabaseAccessToken returns null when Supabase rejects an expired JWT', async () => {
  let getClaimsCallCount = 0;
  const fakeClient = {
    auth: {
      getClaims: async () => {
        getClaimsCallCount += 1;
        throw new Error('Jwt has expired');
      },
    },
  };

  const result = await verifySupabaseAccessToken('expired.jwt.token', fakeClient as any);

  assert.equal(result, null);
  assert.equal(getClaimsCallCount, 1);
});
