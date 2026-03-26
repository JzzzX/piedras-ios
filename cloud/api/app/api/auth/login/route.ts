import { NextRequest } from 'next/server';

import { createRequestContext, errorResponse, jsonResponse } from '@/lib/api-error';
import { AuthValidationError, loginWithPassword } from '@/lib/auth-session';
import { prisma } from '@/lib/db';

export async function POST(req: NextRequest) {
  const context = createRequestContext(req, '/api/auth/login');

  try {
    const body = (await req.json()) as {
      email?: string;
      password?: string;
    };

    const result = await loginWithPassword(prisma, {
      email: body.email ?? '',
      password: body.password ?? '',
    });

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
