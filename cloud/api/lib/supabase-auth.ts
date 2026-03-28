import { createClient, type SupabaseClient } from '@supabase/supabase-js';

import type { SupabaseIdentity } from './auth-context.ts';

interface SupabaseJwtClaims {
  sub?: unknown;
  email?: unknown;
  exp?: unknown;
  session_id?: unknown;
  user_metadata?: {
    display_name?: unknown;
    full_name?: unknown;
    name?: unknown;
  } | null;
}

let cachedVerifierClient: SupabaseClient | null | undefined;

export function identityFromSupabaseClaims(claims: SupabaseJwtClaims): SupabaseIdentity | null {
  const authUserId = normalizeString(claims.sub);
  const email = normalizeEmail(claims.email);
  const exp = normalizePositiveInteger(claims.exp);

  if (!authUserId || !email || !exp) {
    return null;
  }

  return {
    authUserId,
    email,
    displayName: firstNonEmptyString(
      claims.user_metadata?.display_name,
      claims.user_metadata?.full_name,
      claims.user_metadata?.name
    ),
    sessionId: normalizeString(claims.session_id) ?? authUserId,
    expiresAt: new Date(exp * 1000),
  };
}

export async function verifySupabaseAccessToken(token: string): Promise<SupabaseIdentity | null> {
  const client = getSupabaseVerifierClient();
  if (!client) {
    return null;
  }

  const { data, error } = await client.auth.getClaims(token);
  if (error || !data?.claims) {
    return null;
  }

  return identityFromSupabaseClaims(data.claims as SupabaseJwtClaims);
}

function getSupabaseVerifierClient() {
  if (cachedVerifierClient !== undefined) {
    return cachedVerifierClient;
  }

  const supabaseURL = process.env.SUPABASE_URL?.trim();
  const supabaseAnonKey = process.env.SUPABASE_ANON_KEY?.trim();

  if (!supabaseURL || !supabaseAnonKey) {
    cachedVerifierClient = null;
    return cachedVerifierClient;
  }

  cachedVerifierClient = createClient(supabaseURL, supabaseAnonKey, {
    auth: {
      autoRefreshToken: false,
      persistSession: false,
      detectSessionInUrl: false,
    },
  });

  return cachedVerifierClient;
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

function normalizeEmail(value: unknown) {
  const normalized = normalizeString(value);
  return normalized ? normalized.toLowerCase() : null;
}

function normalizePositiveInteger(value: unknown) {
  const numericValue =
    typeof value === 'number'
      ? value
      : typeof value === 'string'
        ? Number.parseInt(value, 10)
        : Number.NaN;

  return Number.isFinite(numericValue) && numericValue > 0 ? numericValue : null;
}

function normalizeString(value: unknown) {
  if (typeof value !== 'string') {
    return null;
  }

  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : null;
}
