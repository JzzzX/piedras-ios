import { NextRequest } from 'next/server';

import { requireInternalAdmin } from '@/lib/api-auth';
import { createRequestContext, errorResponse, jsonResponse } from '@/lib/api-error';
import { generateInviteCode, normalizeInviteCode } from '@/lib/auth';
import { prisma } from '@/lib/db';

export async function GET(req: NextRequest) {
  const context = createRequestContext(req, '/api/internal/invite-codes');
  const internalAuth = requireInternalAdmin(req, context);

  if (internalAuth instanceof Response) {
    return internalAuth;
  }

  try {
    const inviteCodes = await prisma.inviteCode.findMany({
      orderBy: { createdAt: 'desc' },
      include: {
        redeemedByUser: {
          select: {
            id: true,
            email: true,
          },
        },
      },
    });

    return jsonResponse(context, inviteCodes);
  } catch (error) {
    return errorResponse(
      context,
      500,
      error instanceof Error ? `加载邀请码失败：${error.message}` : '加载邀请码失败，请稍后重试。',
      error
    );
  }
}

export async function POST(req: NextRequest) {
  const context = createRequestContext(req, '/api/internal/invite-codes');
  const internalAuth = requireInternalAdmin(req, context);

  if (internalAuth instanceof Response) {
    return internalAuth;
  }

  try {
    const body = (await req.json().catch(() => ({}))) as {
      note?: string;
      code?: string;
    };
    const requestedCode = body.code ? normalizeInviteCode(body.code) : '';
    const code = requestedCode || generateInviteCode();

    const inviteCode = await prisma.inviteCode.create({
      data: {
        code,
        note: body.note?.trim() || '',
      },
    });

    return jsonResponse(context, inviteCode, { status: 201 });
  } catch (error) {
    return errorResponse(
      context,
      500,
      error instanceof Error ? `创建邀请码失败：${error.message}` : '创建邀请码失败，请稍后重试。',
      error
    );
  }
}
