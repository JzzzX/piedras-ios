import { NextRequest } from 'next/server';
import { requireAuthenticatedRequest } from '@/lib/api-auth';
import { createRequestContext, errorResponse, jsonResponse } from '@/lib/api-error';
import { prisma } from '@/lib/db';
import {
  buildMeetingAudioResponse,
  getMeetingAudioPath,
  hasMeetingAudioFile,
  saveMeetingAudioFile,
} from '@/lib/meeting-audio';
import {
  finalizeMeetingTranscriptFromAudio,
  isEmptyTranscriptFinalizationFailure,
} from '@/lib/meeting-transcript-finalizer';
import type { FinalizedTranscript } from '@/lib/meeting-transcript-finalizer';

export const runtime = 'nodejs';

export async function GET(
  req: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  const context = createRequestContext(req, '/api/meetings/[id]/audio');
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
      select: { id: true, audioMimeType: true },
    });

    if (!meeting || !meeting.audioMimeType) {
      return errorResponse(context, 404, '会议音频不存在');
    }

    const exists = await hasMeetingAudioFile(id);
    if (!exists) {
      return errorResponse(context, 404, '会议音频不存在');
    }

    return buildMeetingAudioResponse(id, meeting.audioMimeType, req.headers.get('range'));
  } catch (error) {
    return errorResponse(
      context,
      500,
      error instanceof Error ? `加载会议音频失败：${error.message}` : '加载会议音频失败，请稍后重试。',
      error
    );
  }
}

export async function POST(
  req: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  const context = createRequestContext(req, '/api/meetings/[id]/audio');
  const auth = await requireAuthenticatedRequest(req, context);

  if (auth instanceof Response) {
    return auth;
  }

  try {
    const { id } = await params;
    const shouldFinalizeTranscript = req.nextUrl.searchParams.get('finalizeTranscript') === 'true';
    const formData = await req.formData();
    const file = formData.get('file');
    const duration = Number(formData.get('duration') || 0);
    const mimeType = String(formData.get('mimeType') || '');

    if (!(file instanceof File)) {
      return errorResponse(context, 400, '缺少音频文件');
    }

    const meeting = await prisma.meeting.findFirst({
      where: {
        id,
        workspaceId: auth.workspace.id,
      },
      select: { id: true },
    });

    if (!meeting) {
      return errorResponse(context, 404, '会议不存在，无法保存音频');
    }

    const arrayBuffer = await file.arrayBuffer();
    await saveMeetingAudioFile(id, Buffer.from(arrayBuffer));

    const normalizedDuration = Number.isFinite(duration) && duration > 0 ? Math.round(duration) : null;
    const normalizedMimeType = mimeType || file.type || 'audio/webm';

    if (shouldFinalizeTranscript) {
      let finalizedTranscript: FinalizedTranscript | null = null;
      try {
        finalizedTranscript = await finalizeMeetingTranscriptFromAudio({
          audioPath: getMeetingAudioPath(id),
          mimeType: normalizedMimeType,
          requestId: context.requestId,
          userId: `meeting-${id}`,
        });
      } catch (error) {
        if (!isEmptyTranscriptFinalizationFailure(error)) {
          throw error;
        }
      }

      const hydratedMeeting = await prisma.$transaction(async (tx: any) => {
        const meetingData: Record<string, unknown> = {
          audioMimeType: normalizedMimeType,
          audioDuration: normalizedDuration,
          audioUpdatedAt: new Date(),
        };
        if (finalizedTranscript) {
          meetingData.speakers = JSON.stringify(finalizedTranscript.speakers);
        }

        await tx.meeting.update({
          where: { id },
          data: meetingData,
        });

        if (finalizedTranscript) {
          await tx.transcriptSegment.deleteMany({
            where: { meetingId: id },
          });

          if (finalizedTranscript.segments.length > 0) {
            await tx.transcriptSegment.createMany({
              data: finalizedTranscript.segments.map((segment, index) => ({
                id: crypto.randomUUID(),
                meetingId: id,
                speaker: segment.speaker,
                text: segment.text,
                startTime: segment.startTime,
                endTime: segment.endTime,
                isFinal: segment.isFinal,
                order: index,
              })),
            });
          }
        }

        return tx.meeting.findUnique({
          where: { id },
          include: {
            collection: true,
            segments: { orderBy: { order: 'asc' } },
            chatMessages: { orderBy: { timestamp: 'asc' } },
          },
        });
      });

      return jsonResponse(context, {
        ...hydratedMeeting,
        speakers: hydratedMeeting ? JSON.parse(hydratedMeeting.speakers) : {},
        hasAudio: true,
        audioUrl: `/api/meetings/${id}/audio?t=${hydratedMeeting?.audioUpdatedAt?.getTime() || Date.now()}`,
      });
    }

    const updated = await prisma.meeting.update({
      where: { id },
      data: {
        audioMimeType: normalizedMimeType,
        audioDuration: normalizedDuration,
        audioUpdatedAt: new Date(),
      },
      select: {
        audioMimeType: true,
        audioDuration: true,
        audioUpdatedAt: true,
      },
    });

    return jsonResponse(context, {
      hasAudio: true,
      audioMimeType: updated.audioMimeType,
      audioDuration: updated.audioDuration,
      audioUpdatedAt: updated.audioUpdatedAt?.toISOString() || null,
      audioUrl: `/api/meetings/${id}/audio?t=${updated.audioUpdatedAt?.getTime() || Date.now()}`,
    });
  } catch (error) {
    return errorResponse(
      context,
      500,
      error instanceof Error ? `上传会议音频失败：${error.message}` : '上传会议音频失败，请稍后重试。',
      error
    );
  }
}
