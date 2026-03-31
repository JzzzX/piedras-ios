import { NextRequest } from 'next/server';
import { requireAuthenticatedRequest } from '@/lib/api-auth';
import { createRequestContext, errorResponse, jsonResponse } from '@/lib/api-error';
import { prisma } from '@/lib/db';
import {
  buildMeetingAudioResponse,
  hasMeetingAudioFile,
  saveMeetingAudioFile,
  saveMeetingAudioStream,
} from '@/lib/meeting-audio';
import {
  buildMeetingAudioProcessingStatus,
  queueMeetingAudioProcessing,
  recoverPendingMeetingAudioProcessing,
} from '@/lib/meeting-audio-processing';

export const runtime = 'nodejs';

interface PersistAudioUploadOptions {
  meetingId: string;
  duration: number | null;
  mimeType: string;
  shouldFinalizeTranscript: boolean;
  requestId: string;
}

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
    await recoverPendingMeetingAudioProcessing();
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
    const duration = normalizeDuration(formData.get('duration'));

    if (!(file instanceof File)) {
      return errorResponse(context, 400, '缺少音频文件');
    }

    const mimeType = normalizeMimeType(String(formData.get('mimeType') || ''), file);

    await requireMeetingOwnership(id, auth.workspace.id);

    const arrayBuffer = await file.arrayBuffer();
    await saveMeetingAudioFile(id, Buffer.from(arrayBuffer));
    const payload = await persistAudioUpload({
      meetingId: id,
      duration,
      mimeType,
      shouldFinalizeTranscript,
      requestId: context.requestId,
    });

    return jsonResponse(context, payload);
  } catch (error) {
    return errorResponse(
      context,
      500,
      error instanceof Error ? `上传会议音频失败：${error.message}` : '上传会议音频失败，请稍后重试。',
      error
    );
  }
}

export async function PUT(
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
    const duration = normalizeDuration(req.headers.get('x-audio-duration'));
    const mimeType = normalizeMimeType(req.headers.get('content-type'), null);

    if (!req.body) {
      return errorResponse(context, 400, '缺少音频数据');
    }

    await requireMeetingOwnership(id, auth.workspace.id);
    await saveMeetingAudioStream(id, req.body);

    const payload = await persistAudioUpload({
      meetingId: id,
      duration,
      mimeType,
      shouldFinalizeTranscript,
      requestId: context.requestId,
    });

    return jsonResponse(context, payload);
  } catch (error) {
    return errorResponse(
      context,
      500,
      error instanceof Error ? `上传会议音频失败：${error.message}` : '上传会议音频失败，请稍后重试。',
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
    throw new Error('会议不存在，无法保存音频');
  }
}

async function persistAudioUpload(options: PersistAudioUploadOptions) {
  if (!(await hasMeetingAudioFile(options.meetingId))) {
    throw new Error('会议音频落盘校验失败');
  }

  const requestedAt = options.shouldFinalizeTranscript ? new Date() : null;
  const updated = await prisma.meeting.update({
    where: { id: options.meetingId },
    data: {
      audioMimeType: options.mimeType,
      audioDuration: options.duration,
      audioUpdatedAt: new Date(),
      audioProcessingState: options.shouldFinalizeTranscript ? 'queued' : 'idle',
      audioProcessingError: '',
      audioProcessingAttempts: 0,
      audioProcessingRequestedAt: requestedAt,
      audioProcessingStartedAt: null,
      audioProcessingCompletedAt: null,
    },
    select: {
      audioMimeType: true,
      audioDuration: true,
      audioUpdatedAt: true,
      audioProcessingState: true,
      audioProcessingError: true,
      audioProcessingAttempts: true,
      audioProcessingRequestedAt: true,
      audioProcessingStartedAt: true,
      audioProcessingCompletedAt: true,
    },
  });

  if (options.shouldFinalizeTranscript) {
    await queueMeetingAudioProcessing({
      meetingId: options.meetingId,
      requestId: options.requestId,
    });
  }

  return {
    hasAudio: true,
    audioMimeType: updated.audioMimeType,
    audioDuration: updated.audioDuration,
    audioUpdatedAt: updated.audioUpdatedAt?.toISOString() || null,
    audioUrl: `/api/meetings/${options.meetingId}/audio?t=${updated.audioUpdatedAt?.getTime() || Date.now()}`,
    ...buildMeetingAudioProcessingStatus(updated),
  };
}

function normalizeDuration(value: FormDataEntryValue | string | null) {
  const normalized = Number(value || 0);
  return Number.isFinite(normalized) && normalized > 0 ? Math.round(normalized) : null;
}

function normalizeMimeType(value: string | null | undefined, file: File | null) {
  return value?.trim() || file?.type || 'audio/webm';
}
