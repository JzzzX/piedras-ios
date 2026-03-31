import { NextRequest } from 'next/server';
import { requireAuthenticatedRequest } from '@/lib/api-auth';
import { createRequestContext, errorResponse, jsonResponse } from '@/lib/api-error';
import { prisma } from '@/lib/db';
import { buildMeetingAudioProcessingStatus, recoverPendingMeetingAudioProcessing } from '@/lib/meeting-audio-processing';
import { hasMeetingAudioFile } from '@/lib/meeting-audio';

export const runtime = 'nodejs';

export async function GET(
  req: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  const context = createRequestContext(req, '/api/meetings/[id]/processing-status');
  const auth = await requireAuthenticatedRequest(req, context);

  if (auth instanceof Response) {
    return auth;
  }

  try {
    await recoverPendingMeetingAudioProcessing();
    const { id } = await params;

    const meeting = await prisma.meeting.findFirst({
      where: {
        id,
        workspaceId: auth.workspace.id,
      },
      select: {
        id: true,
        audioMimeType: true,
        audioProcessingState: true,
        audioProcessingError: true,
        audioProcessingAttempts: true,
        audioProcessingRequestedAt: true,
        audioProcessingStartedAt: true,
        audioProcessingCompletedAt: true,
      },
    });

    if (!meeting) {
      return errorResponse(context, 404, '会议不存在');
    }

    return jsonResponse(context, {
      meetingId: meeting.id,
      hasAudio: Boolean(meeting.audioMimeType) && (await hasMeetingAudioFile(meeting.id)),
      ...buildMeetingAudioProcessingStatus(meeting),
    });
  } catch (error) {
    return errorResponse(
      context,
      500,
      error instanceof Error ? `加载处理状态失败：${error.message}` : '加载处理状态失败，请稍后重试。',
      error
    );
  }
}
