import { NextRequest } from 'next/server';

import { requireAuthenticatedRequest } from '@/lib/api-auth';
import { createRequestContext, errorResponse } from '@/lib/api-error';
import { prisma } from '@/lib/db';
import {
  buildMeetingAttachmentResponse,
  deleteMeetingAttachmentFile,
  hasMeetingAttachmentFile,
} from '@/lib/meeting-attachment';

export const runtime = 'nodejs';

export async function GET(
  req: NextRequest,
  { params }: { params: Promise<{ id: string; attachmentId: string }> }
) {
  const context = createRequestContext(req, '/api/meetings/[id]/attachments/[attachmentId]');
  const auth = await requireAuthenticatedRequest(req, context);

  if (auth instanceof Response) {
    return auth;
  }

  try {
    const { id, attachmentId } = await params;
    const attachment = await requireAttachmentOwnership(id, attachmentId, auth.workspace.id);

    if (!(await hasMeetingAttachmentFile(id, attachmentId))) {
      return errorResponse(context, 404, '资料区附件不存在');
    }

    return buildMeetingAttachmentResponse(
      id,
      attachmentId,
      attachment.mimeType,
      attachment.originalName
    );
  } catch (error) {
    return errorResponse(
      context,
      500,
      error instanceof Error ? `加载资料区附件失败：${error.message}` : '加载资料区附件失败，请稍后重试。',
      error
    );
  }
}

export async function DELETE(
  req: NextRequest,
  { params }: { params: Promise<{ id: string; attachmentId: string }> }
) {
  const context = createRequestContext(req, '/api/meetings/[id]/attachments/[attachmentId]');
  const auth = await requireAuthenticatedRequest(req, context);

  if (auth instanceof Response) {
    return auth;
  }

  try {
    const { id, attachmentId } = await params;
    await requireAttachmentOwnership(id, attachmentId, auth.workspace.id);
    await deleteMeetingAttachmentFile(id, attachmentId);
    await prisma.meetingAttachment.delete({
      where: { id: attachmentId },
    });

    return new Response(null, { status: 204 });
  } catch (error) {
    return errorResponse(
      context,
      500,
      error instanceof Error ? `删除资料区附件失败：${error.message}` : '删除资料区附件失败，请稍后重试。',
      error
    );
  }
}

async function requireAttachmentOwnership(meetingId: string, attachmentId: string, workspaceId: string) {
  const attachment = await prisma.meetingAttachment.findFirst({
    where: {
      id: attachmentId,
      meetingId,
      meeting: {
        workspaceId,
      },
    },
    select: {
      id: true,
      mimeType: true,
      originalName: true,
    },
  });

  if (!attachment) {
    throw new Error('资料区附件不存在');
  }

  return attachment;
}
