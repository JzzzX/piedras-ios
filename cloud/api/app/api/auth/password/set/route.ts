import { NextRequest } from 'next/server';

import { createRequestContext, errorResponse, jsonResponse } from '@/lib/api-error';
import { requireAuthenticatedRequest } from '@/lib/api-auth';
import { AuthValidationError } from '@/lib/auth-session';
import { setSupabasePassword } from '@/lib/supabase-password-auth';

export async function POST(req: NextRequest) {
  const context = createRequestContext(req, '/api/auth/password/set');

  try {
    const authContext = await requireAuthenticatedRequest(req, context);
    if (authContext instanceof Response) {
      return authContext;
    }

    if (!authContext.user.authUserId) {
      return errorResponse(context, 400, '当前账号暂不支持在应用内设置密码');
    }

    const body = (await req.json()) as {
      password?: string;
    };

    await setSupabasePassword({
      authUserId: authContext.user.authUserId,
      password: body.password ?? '',
    });

    return jsonResponse(context, { success: true });
  } catch (error) {
    if (error instanceof AuthValidationError) {
      return errorResponse(context, error.status, error.message, error);
    }

    return errorResponse(
      context,
      500,
      error instanceof Error ? `设置密码失败：${error.message}` : '设置密码失败，请稍后重试。',
      error
    );
  }
}
