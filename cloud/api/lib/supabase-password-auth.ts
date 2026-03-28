import type { Prisma, PrismaClient } from '@prisma/client';
import { createClient, type SupabaseClient } from '@supabase/supabase-js';

import { normalizeEmail, isPasswordValid } from './auth.ts';
import { resolveSupabaseUserContext, type SupabaseIdentity } from './auth-context.ts';
import { AuthValidationError, type AuthResult } from './auth-session.ts';

type DatabaseClient = PrismaClient | Prisma.TransactionClient;

export interface SupabaseAuthResult extends AuthResult {
  requiresEmailVerification: boolean;
  verificationEmail: string | null;
}

export interface SupabasePasswordAuthClient {
  auth: {
    signUp(credentials: {
      email: string;
      password: string;
      options?: {
        data?: Record<string, unknown>;
        emailRedirectTo?: string;
      };
    }): Promise<{ data: { user?: unknown; session?: unknown } | null; error: unknown }>;
    signInWithPassword(credentials: {
      email: string;
      password: string;
    }): Promise<{ data: { user?: unknown; session?: unknown } | null; error: unknown }>;
    signInWithOtp(credentials: {
      email: string;
      options?: {
        shouldCreateUser?: boolean;
        data?: Record<string, unknown>;
      };
    }): Promise<{ data: { user?: unknown; session?: unknown } | null; error: unknown }>;
    verifyOtp(credentials: {
      email: string;
      token: string;
      type: 'email';
    }): Promise<{ data: { user?: unknown; session?: unknown } | null; error: unknown }>;
    refreshSession(currentSession?: {
      refresh_token: string;
    }): Promise<{ data: { user?: unknown; session?: unknown } | null; error: unknown }>;
    resetPasswordForEmail(
      email: string,
      options?: { redirectTo?: string }
    ): Promise<{ data: unknown; error: unknown }>;
    resend(credentials: {
      type: 'signup';
      email: string;
      options?: {
        emailRedirectTo?: string;
      };
    }): Promise<{ data: unknown; error: unknown }>;
    admin?: {
      updateUserById(
        uid: string,
        attributes: {
          password?: string;
        }
      ): Promise<{ data: { user?: unknown } | null; error: unknown }>;
    };
  };
}

interface SupabaseAuthUser {
  id?: unknown;
  email?: unknown;
  user_metadata?: {
    display_name?: unknown;
    full_name?: unknown;
    name?: unknown;
  } | null;
}

interface SupabaseSessionLike {
  access_token?: unknown;
  refresh_token?: unknown;
  expires_at?: unknown;
  session_id?: unknown;
}

let cachedPasswordAuthClient: SupabaseClient | null | undefined;
let cachedAdminAuthClient: SupabaseClient | null | undefined;

export function isSupabasePasswordAuthEnabled() {
  return getSupabasePasswordAuthClient() !== null;
}

export function getSupabasePasswordAuthClient(): SupabaseClient | null {
  if (cachedPasswordAuthClient !== undefined) {
    return cachedPasswordAuthClient;
  }

  const supabaseURL = process.env.SUPABASE_URL?.trim();
  const supabaseAnonKey = process.env.SUPABASE_ANON_KEY?.trim();

  if (!supabaseURL || !supabaseAnonKey) {
    cachedPasswordAuthClient = null;
    return cachedPasswordAuthClient;
  }

  cachedPasswordAuthClient = createClient(supabaseURL, supabaseAnonKey, {
    auth: {
      autoRefreshToken: false,
      persistSession: false,
      detectSessionInUrl: false,
    },
  });

  return cachedPasswordAuthClient;
}

export async function registerWithSupabasePassword(
  db: DatabaseClient,
  input: {
    email: string;
    password: string;
    displayName?: string | null;
  },
  options: {
    client?: SupabasePasswordAuthClient | null;
    ensureWorkspace: (input: { userId: string }) => Promise<{ id: string; name: string }>;
  }
): Promise<SupabaseAuthResult> {
  const email = normalizeRequiredEmail(input.email);
  const password = validatePassword(input.password);
  const displayName = sanitizeDisplayName(input.displayName);
  const client = requirePasswordAuthClient(options.client);

  const { data, error } = await client.auth.signUp({
    email,
    password,
    options: {
      data: displayName ? { display_name: displayName } : undefined,
      emailRedirectTo: resolveEmailRedirectURL(),
    },
  });

  if (error) {
    throw mapSupabaseAuthError(error, '注册失败，请稍后重试。');
  }

  const authUser = data?.user as SupabaseAuthUser | undefined;
  const session = data?.session as SupabaseSessionLike | undefined;
  const authContext = await resolveSupabaseUserContext(
    db,
    identityFromSupabaseAuthUser(authUser, session, {
      email,
      displayName: displayName || null,
    }),
    options.ensureWorkspace
  );

  return toSupabaseAuthResult(authContext, session, {
    requiresEmailVerification: !normalizeString(session?.access_token),
    verificationEmail: email,
  });
}

export async function loginWithSupabasePassword(
  db: DatabaseClient,
  input: {
    email: string;
    password: string;
  },
  options: {
    client?: SupabasePasswordAuthClient | null;
    ensureWorkspace: (input: { userId: string }) => Promise<{ id: string; name: string }>;
  }
): Promise<SupabaseAuthResult> {
  const email = normalizeRequiredEmail(input.email);
  const password = requireNonEmptyString(input.password, '邮箱和密码不能为空');
  const client = requirePasswordAuthClient(options.client);

  const { data, error } = await client.auth.signInWithPassword({
    email,
    password,
  });

  if (error) {
    throw mapSupabaseAuthError(error, '登录失败，请稍后重试。');
  }

  const authUser = data?.user as SupabaseAuthUser | undefined;
  const session = data?.session as SupabaseSessionLike | undefined;
  const authContext = await resolveSupabaseUserContext(
    db,
    identityFromSupabaseAuthUser(authUser, session, {
      email,
      displayName: null,
    }),
    options.ensureWorkspace
  );

  return toSupabaseAuthResult(authContext, session, {
    requiresEmailVerification: false,
    verificationEmail: null,
  });
}

export async function refreshSupabaseAuthSession(
  db: DatabaseClient,
  input: {
    refreshToken: string;
  },
  options: {
    client?: SupabasePasswordAuthClient | null;
    ensureWorkspace: (input: { userId: string }) => Promise<{ id: string; name: string }>;
  }
): Promise<SupabaseAuthResult> {
  const refreshToken = requireNonEmptyString(input.refreshToken, 'refresh token 不能为空');
  const client = requirePasswordAuthClient(options.client);

  const { data, error } = await client.auth.refreshSession({
    refresh_token: refreshToken,
  });

  if (error) {
    throw mapSupabaseAuthError(error, '登录态已失效，请重新登录');
  }

  const authUser = (data?.session as { user?: unknown } | undefined)?.user ?? data?.user;
  const session = data?.session as SupabaseSessionLike | undefined;
  const authContext = await resolveSupabaseUserContext(
    db,
    identityFromSupabaseAuthUser(authUser as SupabaseAuthUser | undefined, session, {
      email: null,
      displayName: null,
    }),
    options.ensureWorkspace
  );

  return toSupabaseAuthResult(authContext, session, {
    requiresEmailVerification: false,
    verificationEmail: null,
  });
}

export async function sendSupabaseEmailOTP(
  input: {
    email: string;
    intent: 'login' | 'register';
  },
  options: {
    client?: SupabasePasswordAuthClient | null;
  } = {}
) {
  const email = normalizeRequiredEmail(input.email);
  const client = requirePasswordAuthClient(options.client);

  const { error } = await client.auth.signInWithOtp({
    email,
    options: {
      shouldCreateUser: input.intent === 'register',
    },
  });

  if (error) {
    throw mapSupabaseAuthError(
      error,
      input.intent === 'register' ? '发送注册验证码失败，请稍后重试。' : '发送登录验证码失败，请稍后重试。'
    );
  }
}

export async function loginWithSupabaseEmailOTP(
  db: DatabaseClient,
  input: {
    email: string;
    token: string;
  },
  options: {
    client?: SupabasePasswordAuthClient | null;
    ensureWorkspace: (input: { userId: string }) => Promise<{ id: string; name: string }>;
  }
): Promise<SupabaseAuthResult> {
  return verifySupabaseEmailOTP(
    db,
    {
      email: input.email,
      token: input.token,
      displayName: null,
    },
    options
  );
}

export async function registerWithSupabaseEmailOTP(
  db: DatabaseClient,
  input: {
    email: string;
    token: string;
    displayName?: string | null;
  },
  options: {
    client?: SupabasePasswordAuthClient | null;
    ensureWorkspace: (input: { userId: string }) => Promise<{ id: string; name: string }>;
  }
): Promise<SupabaseAuthResult> {
  return verifySupabaseEmailOTP(
    db,
    {
      email: input.email,
      token: input.token,
      displayName: input.displayName,
    },
    options
  );
}

export async function setSupabasePassword(
  input: {
    authUserId: string;
    password: string;
  },
  options: {
    adminClient?: SupabasePasswordAuthClient | null;
  } = {}
) {
  const authUserId = requireNonEmptyString(input.authUserId, '账号标识不能为空');
  const password = validatePassword(input.password);
  const client = requireAdminAuthClient(options.adminClient);

  const { error } = await client.auth.admin!.updateUserById(authUserId, {
    password,
  });

  if (error) {
    throw mapSupabaseAuthError(error, '设置密码失败，请稍后重试。');
  }
}

export async function requestSupabasePasswordReset(
  input: {
    email: string;
  },
  options: {
    client?: SupabasePasswordAuthClient | null;
  } = {}
) {
  const email = normalizeRequiredEmail(input.email);
  const client = requirePasswordAuthClient(options.client);

  const { error } = await client.auth.resetPasswordForEmail(email, {
    redirectTo: resolveEmailRedirectURL(),
  });

  if (error) {
    throw mapSupabaseAuthError(error, '发送重置密码邮件失败，请稍后重试。');
  }
}

export async function resendSupabaseVerificationEmail(
  input: {
    email: string;
  },
  options: {
    client?: SupabasePasswordAuthClient | null;
  } = {}
) {
  const email = normalizeRequiredEmail(input.email);
  const client = requirePasswordAuthClient(options.client);

  const { error } = await client.auth.resend({
    type: 'signup',
    email,
    options: {
      emailRedirectTo: resolveEmailRedirectURL(),
    },
  });

  if (error) {
    throw mapSupabaseAuthError(error, '发送验证邮件失败，请稍后重试。');
  }
}

function toSupabaseAuthResult(
  authContext: {
    user: { id: string; email: string };
    session: { id: string; expiresAt: Date };
    workspace: { id: string; name: string };
  },
  session: SupabaseSessionLike | undefined,
  options: {
    requiresEmailVerification: boolean;
    verificationEmail: string | null;
  }
): SupabaseAuthResult {
  return {
    user: authContext.user,
    workspace: authContext.workspace,
    session: {
      token: normalizeString(session?.access_token) ?? '',
      refreshToken: normalizeString(session?.refresh_token),
      expiresAt: resolveExpiryDate(session?.expires_at) ?? authContext.session.expiresAt,
    },
    requiresEmailVerification: options.requiresEmailVerification,
    verificationEmail: options.verificationEmail,
  };
}

function identityFromSupabaseAuthUser(
  user: SupabaseAuthUser | undefined,
  session: SupabaseSessionLike | undefined,
  fallback: {
    email: string | null;
    displayName: string | null;
  }
): SupabaseIdentity {
  const authUserId = normalizeString(user?.id);
  const email = normalizeString(user?.email)?.toLowerCase() ?? fallback.email;

  if (!authUserId || !email) {
    throw new AuthValidationError(502, 'Supabase Auth 未返回完整的账号信息');
  }

  return {
    authUserId,
    email,
    displayName:
      firstNonEmptyString(
        user?.user_metadata?.display_name,
        user?.user_metadata?.full_name,
        user?.user_metadata?.name
      ) ?? fallback.displayName,
    sessionId: normalizeString(session?.session_id) ?? authUserId,
    expiresAt: resolveExpiryDate(session?.expires_at) ?? new Date(),
  };
}

function requirePasswordAuthClient(client?: SupabasePasswordAuthClient | null) {
  const resolvedClient = client ?? getSupabasePasswordAuthClient();
  if (!resolvedClient) {
    throw new AuthValidationError(500, 'SUPABASE_URL 或 SUPABASE_ANON_KEY 未配置');
  }

  return resolvedClient;
}

function requireAdminAuthClient(client?: SupabasePasswordAuthClient | null) {
  const resolvedClient = client ?? getSupabaseAdminAuthClient();
  if (!resolvedClient) {
    throw new AuthValidationError(500, 'SUPABASE_URL 或 SUPABASE_SERVICE_ROLE_KEY 未配置');
  }

  if (!resolvedClient.auth.admin?.updateUserById) {
    throw new AuthValidationError(500, 'Supabase 管理端能力不可用');
  }

  return resolvedClient;
}

function normalizeRequiredEmail(value: string) {
  const email = normalizeEmail(value);
  if (!email) {
    throw new AuthValidationError(400, '邮箱不能为空');
  }

  return email;
}

function validatePassword(value: string) {
  if (!isPasswordValid(value)) {
    throw new AuthValidationError(400, '密码至少需要 8 位');
  }

  return value;
}

function requireNonEmptyString(value: string, message: string) {
  const normalized = normalizeString(value);
  if (!normalized) {
    throw new AuthValidationError(400, message);
  }

  return normalized;
}

function sanitizeDisplayName(value?: string | null) {
  return value?.trim() ?? '';
}

function resolveEmailRedirectURL() {
  const redirectURL = process.env.SUPABASE_AUTH_REDIRECT_URL?.trim();
  return redirectURL && redirectURL.length > 0 ? redirectURL : undefined;
}

function getSupabaseAdminAuthClient(): SupabaseClient | null {
  if (cachedAdminAuthClient !== undefined) {
    return cachedAdminAuthClient;
  }

  const supabaseURL = process.env.SUPABASE_URL?.trim();
  const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY?.trim();

  if (!supabaseURL || !serviceRoleKey) {
    cachedAdminAuthClient = null;
    return cachedAdminAuthClient;
  }

  cachedAdminAuthClient = createClient(supabaseURL, serviceRoleKey, {
    auth: {
      autoRefreshToken: false,
      persistSession: false,
      detectSessionInUrl: false,
    },
  });

  return cachedAdminAuthClient;
}

async function verifySupabaseEmailOTP(
  db: DatabaseClient,
  input: {
    email: string;
    token: string;
    displayName?: string | null;
  },
  options: {
    client?: SupabasePasswordAuthClient | null;
    ensureWorkspace: (input: { userId: string }) => Promise<{ id: string; name: string }>;
  }
): Promise<SupabaseAuthResult> {
  const email = normalizeRequiredEmail(input.email);
  const token = requireNonEmptyString(input.token, '验证码不能为空');
  const displayName = sanitizeDisplayName(input.displayName);
  const client = requirePasswordAuthClient(options.client);

  const { data, error } = await client.auth.verifyOtp({
    email,
    token,
    type: 'email',
  });

  if (error) {
    throw mapSupabaseAuthError(error, '验证码校验失败，请稍后重试。');
  }

  const authUser = data?.user as SupabaseAuthUser | undefined;
  const session = data?.session as SupabaseSessionLike | undefined;
  const authContext = await resolveSupabaseUserContext(
    db,
    identityFromSupabaseAuthUser(authUser, session, {
      email,
      displayName: displayName || null,
    }),
    options.ensureWorkspace
  );

  return toSupabaseAuthResult(authContext, session, {
    requiresEmailVerification: false,
    verificationEmail: null,
  });
}

function resolveExpiryDate(value: unknown) {
  const numericValue =
    typeof value === 'number'
      ? value
      : typeof value === 'string'
        ? Number.parseInt(value, 10)
        : Number.NaN;

  return Number.isFinite(numericValue) && numericValue > 0
    ? new Date(numericValue * 1000)
    : null;
}

function mapSupabaseAuthError(error: unknown, fallback: string) {
  const code = normalizeString((error as { code?: unknown } | null)?.code)?.toLowerCase();
  const status = normalizeStatus((error as { status?: unknown } | null)?.status);
  const message = normalizeString((error as { message?: unknown } | null)?.message);
  const normalizedMessage = message?.toLowerCase() ?? '';

  if (
    code === 'invalid_credentials' ||
    code === 'user_not_found' ||
    normalizedMessage.includes('invalid login credentials')
  ) {
    return new AuthValidationError(401, '邮箱或密码错误');
  }

  if (code === 'email_not_confirmed' || normalizedMessage.includes('email not confirmed')) {
    return new AuthValidationError(403, '请先完成邮箱验证');
  }

  if (
    code === 'user_already_exists' ||
    code === 'email_exists' ||
    normalizedMessage.includes('already registered')
  ) {
    return new AuthValidationError(409, '该邮箱已注册');
  }

  if (
    code === 'session_not_found' ||
    code === 'refresh_token_not_found' ||
    code === 'session_expired'
  ) {
    return new AuthValidationError(401, '登录态已失效，请重新登录');
  }

  if (code === 'weak_password') {
    return new AuthValidationError(400, message ?? '密码强度不足');
  }

  if (code === 'otp_expired') {
    return new AuthValidationError(400, '验证码已过期，请重新发送');
  }

  if (
    code === 'validation_failed' ||
    normalizedMessage.includes('token has expired') ||
    normalizedMessage.includes('invalid otp') ||
    normalizedMessage.includes('token is invalid')
  ) {
    return new AuthValidationError(400, '验证码错误或已失效');
  }

  if (code === 'over_request_rate_limit' || code === 'over_email_send_rate_limit') {
    return new AuthValidationError(429, '请求过于频繁，请稍后再试');
  }

  if (status === 401) {
    return new AuthValidationError(401, message ?? '登录态已失效，请重新登录');
  }

  if (status === 429) {
    return new AuthValidationError(429, '请求过于频繁，请稍后再试');
  }

  if (status >= 400 && status < 500) {
    return new AuthValidationError(status, message ?? fallback);
  }

  return new AuthValidationError(status || 502, message ?? fallback);
}

function normalizeStatus(value: unknown) {
  return typeof value === 'number' && Number.isFinite(value) ? value : 0;
}

function firstNonEmptyString(...candidates: unknown[]) {
  for (const candidate of candidates) {
    const normalized = normalizeString(candidate);
    if (normalized) {
      return normalized;
    }
  }

  return null;
}

function normalizeString(value: unknown) {
  if (typeof value !== 'string') {
    return null;
  }

  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : null;
}
