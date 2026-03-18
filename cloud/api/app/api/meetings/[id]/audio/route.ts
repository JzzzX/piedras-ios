import { NextRequest, NextResponse } from 'next/server';
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
  const { id } = await params;

  const meeting = await prisma.meeting.findUnique({
    where: { id },
    select: { id: true, audioMimeType: true },
  });

  if (!meeting || !meeting.audioMimeType) {
    return NextResponse.json({ error: '会议音频不存在' }, { status: 404 });
  }

  const exists = await hasMeetingAudioFile(id);
  if (!exists) {
    return NextResponse.json({ error: '会议音频不存在' }, { status: 404 });
  }

  return buildMeetingAudioResponse(id, meeting.audioMimeType, req.headers.get('range'));
}

export async function POST(
  req: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  const { id } = await params;
  const formData = await req.formData();
  const file = formData.get('file');
  const duration = Number(formData.get('duration') || 0);
  const mimeType = String(formData.get('mimeType') || '');

  if (!(file instanceof File)) {
    return NextResponse.json({ error: '缺少音频文件' }, { status: 400 });
  }

  const meeting = await prisma.meeting.findUnique({
    where: { id },
    select: { id: true },
  });

  if (!meeting) {
    return NextResponse.json({ error: '会议不存在，无法保存音频' }, { status: 404 });
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

  return NextResponse.json({
    hasAudio: true,
    audioMimeType: updated.audioMimeType,
    audioDuration: updated.audioDuration,
    audioUpdatedAt: updated.audioUpdatedAt?.toISOString() || null,
    audioUrl: `/api/meetings/${id}/audio?t=${updated.audioUpdatedAt?.getTime() || Date.now()}`,
  });
}
