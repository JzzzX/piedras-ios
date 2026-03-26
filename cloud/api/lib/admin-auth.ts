import crypto from 'node:crypto';

export const ADMIN_SESSION_COOKIE_NAME = 'piedras_admin_session';
export const ADMIN_SESSION_TTL_MS = 12 * 60 * 60 * 1000;

type VerificationFailureReason = 'expired' | 'malformed' | 'missing' | 'signature_mismatch';

export type AdminSessionVerificationResult =
  | {
      valid: true;
      expiresAt: Date;
    }
  | {
      valid: false;
      reason: VerificationFailureReason;
      expiresAt?: Date;
    };

function signAdminSessionPayload(secret: string, payload: string) {
  return crypto.createHmac('sha256', secret).update(payload).digest('base64url');
}

function secureCompare(left: string, right: string) {
  const leftBuffer = Buffer.from(left);
  const rightBuffer = Buffer.from(right);

  if (leftBuffer.length !== rightBuffer.length) {
    return false;
  }

  return crypto.timingSafeEqual(leftBuffer, rightBuffer);
}

export function isAdminSecretMatch(expectedSecret: string, providedSecret: string) {
  if (!expectedSecret || !providedSecret) {
    return false;
  }

  return secureCompare(expectedSecret, providedSecret);
}

export function createAdminSessionValue(
  secret: string,
  options: {
    now?: Date;
    ttlMs?: number;
  } = {}
) {
  const now = options.now ?? new Date();
  const ttlMs = options.ttlMs ?? ADMIN_SESSION_TTL_MS;
  const payload = Buffer.from(
    JSON.stringify({
      exp: now.getTime() + ttlMs,
    })
  ).toString('base64url');
  const signature = signAdminSessionPayload(secret, payload);

  return `${payload}.${signature}`;
}

export function verifyAdminSessionValue(
  secret: string,
  value: string | null | undefined,
  options: {
    now?: Date;
  } = {}
): AdminSessionVerificationResult {
  if (!value) {
    return {
      valid: false,
      reason: 'missing',
    };
  }

  const now = options.now ?? new Date();
  const [payload, signature, extra] = value.split('.');
  if (!payload || !signature || extra) {
    return {
      valid: false,
      reason: 'malformed',
    };
  }

  const expectedSignature = signAdminSessionPayload(secret, payload);
  if (!secureCompare(expectedSignature, signature)) {
    return {
      valid: false,
      reason: 'signature_mismatch',
    };
  }

  try {
    const decoded = JSON.parse(Buffer.from(payload, 'base64url').toString('utf8')) as {
      exp?: number;
    };
    const expiresAt = new Date(decoded.exp ?? Number.NaN);
    if (Number.isNaN(expiresAt.getTime())) {
      return {
        valid: false,
        reason: 'malformed',
      };
    }

    if (expiresAt.getTime() <= now.getTime()) {
      return {
        valid: false,
        reason: 'expired',
        expiresAt,
      };
    }

    return {
      valid: true,
      expiresAt,
    };
  } catch {
    return {
      valid: false,
      reason: 'malformed',
    };
  }
}

export async function setAdminSessionCookie(secret: string) {
  const { cookies } = await import('next/headers.js');
  const cookieStore = await cookies();
  const expiresAt = new Date(Date.now() + ADMIN_SESSION_TTL_MS);

  cookieStore.set({
    name: ADMIN_SESSION_COOKIE_NAME,
    value: createAdminSessionValue(secret),
    httpOnly: true,
    sameSite: 'lax',
    secure: process.env.NODE_ENV === 'production',
    path: '/',
    expires: expiresAt,
  });

  return expiresAt;
}

export async function clearAdminSessionCookie() {
  const { cookies } = await import('next/headers.js');
  const cookieStore = await cookies();
  cookieStore.set({
    name: ADMIN_SESSION_COOKIE_NAME,
    value: '',
    httpOnly: true,
    sameSite: 'lax',
    secure: process.env.NODE_ENV === 'production',
    path: '/',
    expires: new Date(0),
  });
}

export async function readAdminSessionState() {
  const { cookies } = await import('next/headers.js');
  const configuredSecret = process.env.ADMIN_API_SECRET?.trim();
  const cookieStore = await cookies();
  const cookieValue = cookieStore.get(ADMIN_SESSION_COOKIE_NAME)?.value;

  if (!configuredSecret) {
    return {
      configured: false,
      authenticated: false,
      verification: {
        valid: false as const,
        reason: 'missing' as const,
      },
    };
  }

  const verification = verifyAdminSessionValue(configuredSecret, cookieValue);

  return {
    configured: true,
    authenticated: verification.valid,
    verification,
  };
}
