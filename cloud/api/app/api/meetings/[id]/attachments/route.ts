import { randomUUID } from 'node:crypto';

import { NextRequest } from 'next/server';

import { requireAuthenticatedRequest } from '@/lib/api-auth';
import { createRequestContext, errorResponse, jsonResponse } from '@/lib/api-error';
import { prisma } from '@/lib/db';
import { saveMeetingAttachmentFile } from '@/lib/meeting-attachment';
import { requireStartupBootstrapReady } from '@/lib/startup-bootstrap-guard';

export const runtime = 'nodejs';

export async function GET(
  req: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  const context = createRequestContext(req, '/api/meetings/[id]/attachments');
  const auth = await requireAuthenticatedRequest(req, context);

  if (auth instanceof Response) {
    return auth;
  }

  const startupGuard = requireStartupBootstrapReady(context);
  if (startupGuard) {
    return startupGuard;
  }

  try {
    const { id } = await params;
    await requireMeetingOwnership(id, auth.workspace.id);

    const attachments = await prisma.meetingAttachment.findMany({
      where: { meetingId: id },
      orderBy: { createdAt: 'asc' },
      select: {
        id: true,
        mimeType: true,
        originalName: true,
        extractedText: true,
        createdAt: true,
        updatedAt: true,
      },
    });

    return jsonResponse(
      context,
      attachments.map((attachment) => ({
        ...attachment,
        url: `/api/meetings/${id}/attachments/${attachment.id}`,
      }))
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

export async function POST(
  req: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  const context = createRequestContext(req, '/api/meetings/[id]/attachments');
  const auth = await requireAuthenticatedRequest(req, context);

  if (auth instanceof Response) {
    return auth;
  }

  const startupGuard = requireStartupBootstrapReady(context);
  if (startupGuard) {
    return startupGuard;
  }

  try {
    const { id } = await params;
    await requireMeetingOwnership(id, auth.workspace.id);

    const formData = await req.formData();
    const file = formData.get('file');
    const extractedText = String(formData.get('extractedText') || '').trim();

    if (!(file instanceof File)) {
      return errorResponse(context, 400, '缺少附件文件');
    }

    const attachmentId = randomUUID();
    const arrayBuffer = await file.arrayBuffer();
    const buffer = Buffer.from(arrayBuffer);
    await saveMeetingAttachmentFile(id, attachmentId, buffer);

    const attachment = await prisma.meetingAttachment.create({
      data: {
        id: attachmentId,
        meetingId: id,
        originalName: file.name || `${attachmentId}.bin`,
        mimeType: file.type || 'application/octet-stream',
        fileSize: buffer.byteLength,
        extractedText,
      },
      select: {
        id: true,
        mimeType: true,
        originalName: true,
        extractedText: true,
        createdAt: true,
        updatedAt: true,
      },
    });

    console.log(
      JSON.stringify({
        scope: 'cloud-sync',
        event: 'meeting_attachment_uploaded',
        route: context.route,
        requestId: context.requestId,
        workspaceId: auth.workspace.id,
        meetingId: id,
        attachmentId,
        fileSize: buffer.byteLength,
        mimeType: file.type || 'application/octet-stream',
      })
    );

    return jsonResponse(context, {
      ...attachment,
      url: `/api/meetings/${id}/attachments/${attachment.id}`,
    });
  } catch (error) {
    return errorResponse(
      context,
      500,
      error instanceof Error ? `上传资料区附件失败：${error.message}` : '上传资料区附件失败，请稍后重试。',
      error
    );
  }
}

async function requireMeetingOwnership(meetingId: string, workspaceId: string) {
  const meeting = await prisma.meeting.findFirst({
    where: {
      id: meetingId,
      workspaceId,
    },
    select: { id: true },
  });

  if (!meeting) {
    throw new Error('会议不存在，无法保存资料区附件');
  }
}
