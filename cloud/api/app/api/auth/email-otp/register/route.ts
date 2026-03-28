import { NextRequest } from 'next/server';

import { createRequestContext, errorResponse, jsonResponse } from '@/lib/api-error';
import { AuthValidationError } from '@/lib/auth-session';
import { prisma } from '@/lib/db';
import { registerWithSupabaseEmailOTP } from '@/lib/supabase-password-auth';
import { ensureDefaultWorkspaceForUser } from '@/lib/user-workspace-db';

export async function POST(req: NextRequest) {
  const context = createRequestContext(req, '/api/auth/email-otp/register');

  try {
    const body = (await req.json()) as {
      email?: string;
      token?: string;
      displayName?: string;
    };

    const result = await registerWithSupabaseEmailOTP(
      prisma,
      {
        email: body.email ?? '',
        token: body.token ?? '',
        displayName: body.displayName,
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
      error instanceof Error ? `邮箱验证码注册失败：${error.message}` : '邮箱验证码注册失败，请稍后重试。',
      error
    );
  }
}
