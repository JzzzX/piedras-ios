import { NextRequest } from 'next/server';

import { createRequestContext, errorResponse, jsonResponse } from '@/lib/api-error';
import { AuthValidationError, registerWithInviteCode } from '@/lib/auth-session';
import { prisma } from '@/lib/db';
import {
  isSupabasePasswordAuthEnabled,
  registerWithSupabasePassword,
} from '@/lib/supabase-password-auth';
import { ensureDefaultWorkspaceForUser } from '@/lib/user-workspace-db';

export async function POST(req: NextRequest) {
  const context = createRequestContext(req, '/api/auth/register');

  try {
    const body = (await req.json()) as {
      email?: string;
      password?: string;
      inviteCode?: string;
      displayName?: string;
    };

    const result = isSupabasePasswordAuthEnabled()
      ? await registerWithSupabasePassword(
          prisma,
          {
            email: body.email ?? '',
            password: body.password ?? '',
            displayName: body.displayName,
          },
          {
            ensureWorkspace: (input) => ensureDefaultWorkspaceForUser(prisma, input),
          }
        )
      : await registerWithInviteCode(prisma, {
          email: body.email ?? '',
          password: body.password ?? '',
          inviteCode: body.inviteCode ?? '',
          displayName: body.displayName,
        });

    return jsonResponse(context, result);
  } catch (error) {
    if (error instanceof AuthValidationError) {
      return errorResponse(context, error.status, error.message, error);
    }

    return errorResponse(
      context,
      500,
      error instanceof Error ? `注册失败：${error.message}` : '注册失败，请稍后重试。',
      error
    );
  }
}
