import { NextRequest } from 'next/server';

import { requireInternalAdmin } from '@/lib/api-auth';
import { createRequestContext, errorResponse, jsonResponse } from '@/lib/api-error';
import { prisma } from '@/lib/db';

export async function POST(
  req: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  const context = createRequestContext(req, '/api/internal/invite-codes/[id]/revoke');
  const internalAuth = requireInternalAdmin(req, context);

  if (internalAuth instanceof Response) {
    return internalAuth;
  }

  try {
    const { id } = await params;

    const inviteCode = await prisma.inviteCode.update({
      where: { id },
      data: { isRevoked: true },
    });

    return jsonResponse(context, inviteCode);
  } catch (error) {
    return errorResponse(
      context,
      500,
      error instanceof Error ? `停用邀请码失败：${error.message}` : '停用邀请码失败，请稍后重试。',
      error
    );
  }
}
