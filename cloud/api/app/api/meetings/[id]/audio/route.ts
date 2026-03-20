import { NextRequest } from 'next/server';
import { createRequestContext, errorResponse, jsonResponse } from '@/lib/api-error';
import { prisma } from '@/lib/db';
import {
  buildMeetingAudioResponse,
  hasMeetingAudioFile,
  saveMeetingAudioFile,
} from '@/lib/meeting-audio';

export const runtime = 'nodejs';

export async function GET(
  req: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  const context = createRequestContext(req, '/api/meetings/[id]/audio');

  try {
    const { id } = await params;

    const meeting = await prisma.meeting.findUnique({
      where: { id },
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

  try {
    const { id } = await params;
    const formData = await req.formData();
    const file = formData.get('file');
    const duration = Number(formData.get('duration') || 0);
    const mimeType = String(formData.get('mimeType') || '');

    if (!(file instanceof File)) {
      return errorResponse(context, 400, '缺少音频文件');
    }

    const meeting = await prisma.meeting.findUnique({
      where: { id },
      select: { id: true },
    });

    if (!meeting) {
      return errorResponse(context, 404, '会议不存在，无法保存音频');
    }

    const arrayBuffer = await file.arrayBuffer();
    await saveMeetingAudioFile(id, Buffer.from(arrayBuffer));

    const updated = await prisma.meeting.update({
      where: { id },
      data: {
        audioMimeType: mimeType || file.type || 'audio/webm',
        audioDuration: Number.isFinite(duration) && duration > 0 ? Math.round(duration) : null,
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
