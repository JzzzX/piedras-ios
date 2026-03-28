import { NextRequest } from 'next/server';

import { createRequestContext, errorResponse, jsonResponse } from '@/lib/api-error';
import { AuthValidationError } from '@/lib/auth-session';
import { prisma } from '@/lib/db';
import {
  isSupabasePasswordAuthEnabled,
  refreshSupabaseAuthSession,
} from '@/lib/supabase-password-auth';
import { ensureDefaultWorkspaceForUser } from '@/lib/user-workspace-db';

export async function POST(req: NextRequest) {
  const context = createRequestContext(req, '/api/auth/refresh');

  try {
    if (!isSupabasePasswordAuthEnabled()) {
      return errorResponse(context, 501, '当前环境未启用 Supabase 登录刷新');
    }

    const body = (await req.json()) as {
      refreshToken?: string;
    };

    const result = await refreshSupabaseAuthSession(
      prisma,
      {
        refreshToken: body.refreshToken ?? '',
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
      error instanceof Error ? `刷新登录态失败：${error.message}` : '刷新登录态失败，请稍后重试。',
      error
    );
  }
}
