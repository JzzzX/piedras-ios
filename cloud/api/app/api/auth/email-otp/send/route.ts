import { NextRequest } from 'next/server';

import { createRequestContext, errorResponse, jsonResponse } from '@/lib/api-error';
import { AuthValidationError } from '@/lib/auth-session';
import { sendSupabaseEmailOTP } from '@/lib/supabase-password-auth';

export async function POST(req: NextRequest) {
  const context = createRequestContext(req, '/api/auth/email-otp/send');

  try {
    const body = (await req.json()) as {
      email?: string;
      intent?: 'login' | 'register';
    };

    const intent = body.intent === 'register' ? 'register' : 'login';
    await sendSupabaseEmailOTP({
      email: body.email ?? '',
      intent,
    });

    return jsonResponse(context, { success: true, intent });
  } catch (error) {
    if (error instanceof AuthValidationError) {
      return errorResponse(context, error.status, error.message, error);
    }

    return errorResponse(
      context,
      500,
      error instanceof Error ? `发送邮箱验证码失败：${error.message}` : '发送邮箱验证码失败，请稍后重试。',
      error
    );
  }
}
