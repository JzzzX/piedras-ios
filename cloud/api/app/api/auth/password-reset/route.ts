import { NextRequest } from 'next/server';

import { createRequestContext, errorResponse, jsonResponse } from '@/lib/api-error';
import { AuthValidationError } from '@/lib/auth-session';
import {
  isSupabasePasswordAuthEnabled,
  requestSupabasePasswordReset,
} from '@/lib/supabase-password-auth';

export async function POST(req: NextRequest) {
  const context = createRequestContext(req, '/api/auth/password-reset');

  try {
    if (!isSupabasePasswordAuthEnabled()) {
      return errorResponse(context, 501, '当前环境未启用 Supabase 密码重置');
    }

    const body = (await req.json()) as {
      email?: string;
    };

    await requestSupabasePasswordReset({
      email: body.email ?? '',
    });

    return jsonResponse(context, { success: true });
  } catch (error) {
    if (error instanceof AuthValidationError) {
      return errorResponse(context, error.status, error.message, error);
    }

    return errorResponse(
      context,
      500,
      error instanceof Error ? `发送重置密码邮件失败：${error.message}` : '发送重置密码邮件失败，请稍后重试。',
      error
    );
  }
}
