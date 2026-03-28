import { NextRequest } from 'next/server';

import { createRequestContext, errorResponse, jsonResponse } from '@/lib/api-error';
import { normalizeEmail } from '@/lib/auth';
import { AuthValidationError, loginWithPassword } from '@/lib/auth-session';
import { prisma } from '@/lib/db';
import {
  isSupabasePasswordAuthEnabled,
  loginWithSupabasePassword,
} from '@/lib/supabase-password-auth';
import { ensureDefaultWorkspaceForUser } from '@/lib/user-workspace-db';

export async function POST(req: NextRequest) {
  const context = createRequestContext(req, '/api/auth/login');

  try {
    const body = (await req.json()) as {
      email?: string;
      password?: string;
    };

    let result;

    if (isSupabasePasswordAuthEnabled()) {
      try {
        result = await loginWithSupabasePassword(
          prisma,
          {
            email: body.email ?? '',
            password: body.password ?? '',
          },
          {
            ensureWorkspace: (input) => ensureDefaultWorkspaceForUser(prisma, input),
          }
        );
      } catch (error) {
        const shouldFallback =
          error instanceof AuthValidationError &&
          error.status === 401 &&
          (await shouldFallbackToLegacyPasswordLogin(body.email ?? ''));

        if (!shouldFallback) {
          throw error;
        }

        result = await loginWithPassword(prisma, {
          email: body.email ?? '',
          password: body.password ?? '',
        });
      }
    } else {
      result = await loginWithPassword(prisma, {
        email: body.email ?? '',
        password: body.password ?? '',
      });
    }

    return jsonResponse(context, result);
  } catch (error) {
    if (error instanceof AuthValidationError) {
      return errorResponse(context, error.status, error.message, error);
    }

    return errorResponse(
      context,
      500,
      error instanceof Error ? `登录失败：${error.message}` : '登录失败，请稍后重试。',
      error
    );
  }
}

async function shouldFallbackToLegacyPasswordLogin(email: string) {
  const normalizedEmail = normalizeEmail(email);
  if (!normalizedEmail) {
    return false;
  }

  const user = await prisma.user.findUnique({
    where: { email: normalizedEmail },
    select: {
      authUserId: true,
      passwordHash: true,
    },
  });

  return Boolean(user?.passwordHash && !user.authUserId);
}
