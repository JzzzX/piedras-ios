import assert from 'node:assert/strict';
import test from 'node:test';

import {
  loginWithSupabaseEmailOTP,
  loginWithSupabasePassword,
  refreshSupabaseAuthSession,
  registerWithSupabaseEmailOTP,
  registerWithSupabasePassword,
  sendSupabaseEmailOTP,
  setSupabasePassword,
  requestSupabasePasswordReset,
  resendSupabaseVerificationEmail,
} from './supabase-password-auth.ts';

test('registerWithSupabasePassword creates a local user and marks email verification as pending', async () => {
  const signUpCalls: Array<Record<string, unknown>> = [];
  const createdUsers: string[] = [];
  const fakeClient = {
    auth: {
      signUp: async (payload: Record<string, unknown>) => {
        signUpCalls.push(payload);
        return {
          data: {
            user: {
              id: 'auth-signup-1',
              email: 'signup@example.com',
              user_metadata: {
                display_name: 'Signup User',
              },
            },
            session: null,
          },
          error: null,
        };
      },
    },
  };
  const fakeDb = {
    user: {
      findUnique: async () => null,
      findFirst: async () => null,
      update: async () => {
        throw new Error('should not update when registering a new Supabase user');
      },
      create: async ({ data }: any) => {
        createdUsers.push(`${data.email}:${data.authUserId}:${data.displayName}`);
        return {
          id: 'user-signup-1',
          email: data.email,
          authUserId: data.authUserId,
          displayName: data.displayName,
        };
      },
    },
  };

  const result = await registerWithSupabasePassword(
    fakeDb as any,
    {
      email: 'signup@example.com',
      password: 'password-123',
      displayName: 'Signup User',
    },
    {
      client: fakeClient as any,
      ensureWorkspace: async () => ({ id: 'workspace-signup', name: 'Signup Space' }),
    }
  );

  assert.equal(result.user.id, 'user-signup-1');
  assert.equal(result.requiresEmailVerification, true);
  assert.equal(result.verificationEmail, 'signup@example.com');
  assert.equal(result.session.token, '');
  assert.deepEqual(createdUsers, ['signup@example.com:auth-signup-1:Signup User']);
  assert.equal(signUpCalls.length, 1);
});

test('loginWithSupabasePassword reuses a linked user and returns access and refresh tokens', async () => {
  const fakeClient = {
    auth: {
      signInWithPassword: async () => ({
        data: {
          user: {
            id: 'auth-login-1',
            email: 'login@example.com',
            user_metadata: {
              display_name: 'Login User',
            },
          },
          session: {
            session_id: 'session-login-1',
            access_token: 'access-token-1',
            refresh_token: 'refresh-token-1',
            expires_at: 1_900_000_000,
          },
        },
        error: null,
      }),
    },
  };
  const fakeDb = {
    user: {
      findUnique: async ({ where }: any) => {
        if (where.authUserId === 'auth-login-1') {
          return {
            id: 'user-login-1',
            email: 'login@example.com',
            authUserId: 'auth-login-1',
            displayName: 'Login User',
          };
        }
        return null;
      },
      findFirst: async () => null,
      update: async () => {
        throw new Error('should not update an already-linked user');
      },
      create: async () => {
        throw new Error('should not create an already-linked user');
      },
    },
  };

  const result = await loginWithSupabasePassword(
    fakeDb as any,
    {
      email: 'login@example.com',
      password: 'password-123',
    },
    {
      client: fakeClient as any,
      ensureWorkspace: async () => ({ id: 'workspace-login', name: 'Login Space' }),
    }
  );

  assert.equal(result.user.id, 'user-login-1');
  assert.equal(result.requiresEmailVerification, false);
  assert.equal(result.session.token, 'access-token-1');
  assert.equal(result.session.refreshToken, 'refresh-token-1');
  assert.equal(result.workspace.id, 'workspace-login');
});

test('refreshSupabaseAuthSession updates tokens for an existing Supabase user', async () => {
  const fakeClient = {
    auth: {
      refreshSession: async () => ({
        data: {
          session: {
            session_id: 'session-refresh-1',
            access_token: 'access-token-2',
            refresh_token: 'refresh-token-2',
            expires_at: 1_900_000_100,
            user: {
              id: 'auth-refresh-1',
              email: 'refresh@example.com',
            },
          },
        },
        error: null,
      }),
    },
  };
  const fakeDb = {
    user: {
      findUnique: async ({ where }: any) => {
        if (where.authUserId === 'auth-refresh-1') {
          return {
            id: 'user-refresh-1',
            email: 'refresh@example.com',
            authUserId: 'auth-refresh-1',
            displayName: '',
          };
        }
        return null;
      },
      findFirst: async () => null,
      update: async () => {
        throw new Error('should not update when user is already linked');
      },
      create: async () => {
        throw new Error('should not create when user is already linked');
      },
    },
  };

  const result = await refreshSupabaseAuthSession(
    fakeDb as any,
    {
      refreshToken: 'refresh-token-1',
    },
    {
      client: fakeClient as any,
      ensureWorkspace: async () => ({ id: 'workspace-refresh', name: 'Refresh Space' }),
    }
  );

  assert.equal(result.session.token, 'access-token-2');
  assert.equal(result.session.refreshToken, 'refresh-token-2');
  assert.equal(result.user.id, 'user-refresh-1');
});

test('password reset and resend verification call Supabase auth endpoints', async () => {
  const calls: string[] = [];
  const fakeClient = {
    auth: {
      resetPasswordForEmail: async (email: string) => {
        calls.push(`reset:${email}`);
        return { data: {}, error: null };
      },
      resend: async ({ email }: { email: string }) => {
        calls.push(`resend:${email}`);
        return { data: {}, error: null };
      },
    },
  };

  await requestSupabasePasswordReset(
    { email: 'reset@example.com' },
    { client: fakeClient as any }
  );
  await resendSupabaseVerificationEmail(
    { email: 'verify@example.com' },
    { client: fakeClient as any }
  );

  assert.deepEqual(calls, ['reset:reset@example.com', 'resend:verify@example.com']);
});

test('sendSupabaseEmailOTP sends register OTP with user creation enabled', async () => {
  const calls: Array<Record<string, unknown>> = [];
  const fakeClient = {
    auth: {
      signInWithOtp: async (payload: Record<string, unknown>) => {
        calls.push(payload);
        return {
          data: {
            user: null,
            session: null,
          },
          error: null,
        };
      },
    },
  };

  await sendSupabaseEmailOTP(
    {
      email: 'register@example.com',
      intent: 'register',
    },
    { client: fakeClient as any }
  );

  assert.equal(calls.length, 1);
  assert.equal(calls[0].email, 'register@example.com');
  assert.deepEqual(calls[0].options, {
    shouldCreateUser: true,
  });
});

test('sendSupabaseEmailOTP sends login OTP without creating a new user', async () => {
  const calls: Array<Record<string, unknown>> = [];
  const fakeClient = {
    auth: {
      signInWithOtp: async (payload: Record<string, unknown>) => {
        calls.push(payload);
        return {
          data: {
            user: null,
            session: null,
          },
          error: null,
        };
      },
    },
  };

  await sendSupabaseEmailOTP(
    {
      email: 'login@example.com',
      intent: 'login',
    },
    { client: fakeClient as any }
  );

  assert.equal(calls.length, 1);
  assert.equal(calls[0].email, 'login@example.com');
  assert.deepEqual(calls[0].options, {
    shouldCreateUser: false,
  });
});

test('loginWithSupabaseEmailOTP exchanges email token for a session without creating a user', async () => {
  const calls: Array<Record<string, unknown>> = [];
  const fakeClient = {
    auth: {
      verifyOtp: async (payload: Record<string, unknown>) => {
        calls.push(payload);
        return {
          data: {
            user: {
              id: 'auth-otp-login-1',
              email: 'otp-login@example.com',
            },
            session: {
              session_id: 'session-otp-login-1',
              access_token: 'access-token-otp-login',
              refresh_token: 'refresh-token-otp-login',
              expires_at: 1_900_000_200,
            },
          },
          error: null,
        };
      },
    },
  };
  const fakeDb = {
    user: {
      findUnique: async ({ where }: any) => {
        if (where.authUserId === 'auth-otp-login-1') {
          return {
            id: 'user-otp-login-1',
            email: 'otp-login@example.com',
            authUserId: 'auth-otp-login-1',
            displayName: '',
          };
        }
        return null;
      },
      findFirst: async () => null,
      update: async () => {
        throw new Error('should not update linked otp login user');
      },
      create: async () => {
        throw new Error('should not create linked otp login user');
      },
    },
  };

  const result = await loginWithSupabaseEmailOTP(
    fakeDb as any,
    {
      email: 'otp-login@example.com',
      token: '123456',
    },
    {
      client: fakeClient as any,
      ensureWorkspace: async () => ({ id: 'workspace-otp-login', name: 'OTP Login Space' }),
    }
  );

  assert.deepEqual(calls, [
    {
      email: 'otp-login@example.com',
      token: '123456',
      type: 'email',
    },
  ]);
  assert.equal(result.user.id, 'user-otp-login-1');
  assert.equal(result.session.token, 'access-token-otp-login');
  assert.equal(result.session.refreshToken, 'refresh-token-otp-login');
});

test('registerWithSupabaseEmailOTP creates a local user after OTP verification', async () => {
  const calls: Array<Record<string, unknown>> = [];
  const createdUsers: string[] = [];
  const fakeClient = {
    auth: {
      verifyOtp: async (payload: Record<string, unknown>) => {
        calls.push(payload);
        return {
          data: {
            user: {
              id: 'auth-otp-register-1',
              email: 'otp-register@example.com',
            },
            session: {
              session_id: 'session-otp-register-1',
              access_token: 'access-token-otp-register',
              refresh_token: 'refresh-token-otp-register',
              expires_at: 1_900_000_300,
            },
          },
          error: null,
        };
      },
    },
  };
  const fakeDb = {
    user: {
      findUnique: async () => null,
      findFirst: async () => null,
      update: async () => {
        throw new Error('should not update when registering via otp');
      },
      create: async ({ data }: any) => {
        createdUsers.push(`${data.email}:${data.authUserId}:${data.displayName}`);
        return {
          id: 'user-otp-register-1',
          email: data.email,
          authUserId: data.authUserId,
          displayName: data.displayName,
        };
      },
    },
  };

  const result = await registerWithSupabaseEmailOTP(
    fakeDb as any,
    {
      email: 'otp-register@example.com',
      token: '654321',
      displayName: 'OTP User',
    },
    {
      client: fakeClient as any,
      ensureWorkspace: async () => ({ id: 'workspace-otp-register', name: 'OTP Register Space' }),
    }
  );

  assert.deepEqual(calls, [
    {
      email: 'otp-register@example.com',
      token: '654321',
      type: 'email',
    },
  ]);
  assert.deepEqual(createdUsers, ['otp-register@example.com:auth-otp-register-1:OTP User']);
  assert.equal(result.user.id, 'user-otp-register-1');
  assert.equal(result.session.token, 'access-token-otp-register');
});

test('setSupabasePassword updates the authenticated supabase user password via admin api', async () => {
  const calls: Array<{ uid: string; password: string }> = [];
  const fakeAdminClient = {
    auth: {
      admin: {
        updateUserById: async (uid: string, attributes: { password?: string }) => {
          calls.push({ uid, password: attributes.password ?? '' });
          return {
            data: {
              user: {
                id: uid,
              },
            },
            error: null,
          };
        },
      },
    },
  };

  await setSupabasePassword(
    {
      authUserId: 'auth-user-set-password-1',
      password: 'password-123',
    },
    {
      adminClient: fakeAdminClient as any,
    }
  );

  assert.deepEqual(calls, [
    {
      uid: 'auth-user-set-password-1',
      password: 'password-123',
    },
  ]);
});
