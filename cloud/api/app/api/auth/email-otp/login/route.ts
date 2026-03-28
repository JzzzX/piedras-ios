import { NextRequest } from 'next/server';

import { createRequestContext, errorResponse, jsonResponse } from '@/lib/api-error';
import { AuthValidationError } from '@/lib/auth-session';
import { prisma } from '@/lib/db';
import { loginWithSupabaseEmailOTP } from '@/lib/supabase-password-auth';
import { ensureDefaultWorkspaceForUser } from '@/lib/user-workspace-db';

export async function POST(req: NextRequest) {
  const context = createRequestContext(req, '/api/auth/email-otp/login');

  try {
    const body = (await req.json()) as {
      email?: string;
      token?: string;
    };

    const result = await loginWithSupabaseEmailOTP(
      prisma,
      {
        email: body.email ?? '',
        token: body.token ?? '',
      },
      {
        ensureWorkspace: (input) => ensureDefaultWorkspaceForUser(prisma, input),
      }
    );

    return jsonResponse(context, result);
  } catch (error) {
    if (error instanceof AuthValidationError) {
      return errorResponse(context, error.status, error.message, error);
    }

    return errorResponse(
      context,
      500,
      error instanceof Error ? `邮箱验证码登录失败：${error.message}` : '邮箱验证码登录失败，请稍后重试。',
      error
    );
  }
}
