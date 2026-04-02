import { NextRequest } from 'next/server';
import { requireAuthenticatedRequest } from '@/lib/api-auth';
import { createRequestContext, errorResponse, jsonResponse } from '@/lib/api-error';
import { prisma } from '@/lib/db';
import {
  buildMeetingAudioEnhanceStatus,
  persistMeetingAudioEnhanceRequest,
  queueMeetingAudioEnhanceProcessing,
  recoverPendingMeetingAudioEnhanceProcessing,
} from '@/lib/meeting-audio-enhance-processing';
import { hasMeetingAudioFile } from '@/lib/meeting-audio';

export const runtime = 'nodejs';

export async function GET(
  req: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  const context = createRequestContext(req, '/api/meetings/[id]/ai-notes/audio');
  const auth = await requireAuthenticatedRequest(req, context);

  if (auth instanceof Response) {
    return auth;
  }

  try {
    await recoverPendingMeetingAudioEnhanceProcessing();
    const { id } = await params;
    const meeting = await prisma.meeting.findFirst({
      where: {
        id,
        workspaceId: auth.workspace.id,
      },
      select: {
        id: true,
        audioMimeType: true,
        audioEnhancedNotes: true,
        audioEnhancedNotesStatus: true,
        audioEnhancedNotesError: true,
        audioEnhancedNotesUpdatedAt: true,
        audioEnhancedNotesProvider: true,
        audioEnhancedNotesModel: true,
        audioEnhancedNotesAttempts: true,
        audioEnhancedNotesRequestedAt: true,
        audioEnhancedNotesStartedAt: true,
      },
    });

    if (!meeting) {
      return errorResponse(context, 404, '会议不存在');
    }

    return jsonResponse(context, {
      meetingId: meeting.id,
      hasAudio: Boolean(meeting.audioMimeType) && (await hasMeetingAudioFile(meeting.id)),
      ...buildMeetingAudioEnhanceStatus(meeting),
    });
  } catch (error) {
    return errorResponse(
      context,
      500,
      error instanceof Error ? `加载音频 AI 笔记状态失败：${error.message}` : '加载音频 AI 笔记状态失败，请稍后重试。',
      error
    );
  }
}

export async function POST(
  req: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  const context = createRequestContext(req, '/api/meetings/[id]/ai-notes/audio');
  const auth = await requireAuthenticatedRequest(req, context);

  if (auth instanceof Response) {
    return auth;
  }

  try {
    const { id } = await params;
    const meeting = await prisma.meeting.findFirst({
      where: {
        id,
        workspaceId: auth.workspace.id,
      },
      select: {
        id: true,
        audioMimeType: true,
      },
    });

    if (!meeting) {
      return errorResponse(context, 404, '会议不存在');
    }

    if (!meeting.audioMimeType || !(await hasMeetingAudioFile(meeting.id))) {
      return errorResponse(context, 409, '会议音频不存在，请先完成音频上传。', undefined, {
        logLevel: 'silent',
      });
    }

    const payload = await req.json();
    const persisted = await persistMeetingAudioEnhanceRequest(meeting.id, payload);
    await queueMeetingAudioEnhanceProcessing({
      meetingId: meeting.id,
      requestId: context.requestId,
    });

    return jsonResponse(context, {
      meetingId: meeting.id,
      hasAudio: true,
      ...buildMeetingAudioEnhanceStatus(persisted),
    });
  } catch (error) {
    return errorResponse(
      context,
      502,
      error instanceof Error ? `音频 AI 笔记任务提交失败：${error.message}` : '音频 AI 笔记任务提交失败，请稍后重试。',
      error
    );
  }
}
