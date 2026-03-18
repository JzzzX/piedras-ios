import { NextRequest, NextResponse } from 'next/server';
import { prisma } from '@/lib/db';
import { deleteMeetingAudioFile, hasMeetingAudioFile } from '@/lib/meeting-audio';
import { resolveWorkspaceId } from '@/lib/default-workspace';

// GET /api/meetings/[id] — 获取单个会议详情
export async function GET(
  _req: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  const { id } = await params;

  const meeting = await prisma.meeting.findUnique({
    where: { id },
    include: {
      collection: true,
      segments: { orderBy: { order: 'asc' } },
      chatMessages: { orderBy: { timestamp: 'asc' } },
    },
  });

  if (!meeting) {
    return NextResponse.json({ error: '会议不存在' }, { status: 404 });
  }

  const hasAudio =
    Boolean(meeting.audioMimeType) && (await hasMeetingAudioFile(meeting.id));

  return NextResponse.json({
    ...meeting,
    speakers: JSON.parse(meeting.speakers),
    hasAudio,
    audioUrl: hasAudio
      ? `/api/meetings/${meeting.id}/audio?t=${meeting.audioUpdatedAt?.getTime() || 0}`
      : null,
  });
}

// PUT /api/meetings/[id] — 更新会议
export async function PUT(
  req: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  const { id } = await params;
  const body = await req.json();
  const {
    title,
    status,
    duration,
    collectionId,
    workspaceId,
    userNotes,
    enhancedNotes,
    enhanceRecipeId,
    roundLabel,
    interviewerName,
    recommendation,
    handoffNote,
    speakers,
    segments,
    chatMessages,
  } = body;
  const resolvedWorkspaceId =
    workspaceId !== undefined ? await resolveWorkspaceId(workspaceId) : undefined;

  // 更新会议基本信息
  const updateData: Record<string, unknown> = {};
  if (title !== undefined) updateData.title = title;
  if (status !== undefined) updateData.status = status;
  if (duration !== undefined) updateData.duration = duration;
  if (collectionId !== undefined) updateData.collectionId = collectionId || null;
  if (resolvedWorkspaceId !== undefined) updateData.workspaceId = resolvedWorkspaceId;
  if (userNotes !== undefined) updateData.userNotes = userNotes;
  if (enhancedNotes !== undefined) updateData.enhancedNotes = enhancedNotes;
  if (enhanceRecipeId !== undefined) updateData.enhanceRecipeId = enhanceRecipeId || null;
  if (roundLabel !== undefined) updateData.roundLabel = roundLabel;
  if (interviewerName !== undefined) updateData.interviewerName = interviewerName;
  if (recommendation !== undefined) updateData.recommendation = recommendation;
  if (handoffNote !== undefined) updateData.handoffNote = handoffNote;
  if (speakers !== undefined) updateData.speakers = JSON.stringify(speakers);

  const meeting = await prisma.meeting.update({
    where: { id },
    data: updateData,
  });

  // 如果传入了 segments，替换全部
  if (segments) {
    await prisma.transcriptSegment.deleteMany({ where: { meetingId: id } });
    await prisma.transcriptSegment.createMany({
      data: segments.map(
        (s: { id: string; speaker: string; text: string; startTime: number; endTime: number; isFinal: boolean }, i: number) => ({
          id: s.id,
          meetingId: id,
          speaker: s.speaker,
          text: s.text,
          startTime: s.startTime,
          endTime: s.endTime,
          isFinal: s.isFinal,
          order: i,
        })
      ),
    });
  }

  // 如果传入了 chatMessages，替换全部
  if (chatMessages) {
    await prisma.chatMessage.deleteMany({ where: { meetingId: id } });
    await prisma.chatMessage.createMany({
      data: chatMessages.map(
        (m: { id: string; role: string; content: string; timestamp: number; recipeId?: string; templateId?: string }) => ({
          id: m.id,
          meetingId: id,
          role: m.role,
          content: m.content,
          timestamp: m.timestamp,
          templateId: m.recipeId || m.templateId || null,
        })
      ),
    });
  }

  const hydratedMeeting = await prisma.meeting.findUnique({
    where: { id: meeting.id },
    include: {
      collection: true,
      segments: { orderBy: { order: 'asc' } },
      chatMessages: { orderBy: { timestamp: 'asc' } },
    },
  });

  const hasAudio =
    Boolean(hydratedMeeting?.audioMimeType) &&
    hydratedMeeting
      ? await hasMeetingAudioFile(hydratedMeeting.id)
      : false;

  return NextResponse.json({
    ...hydratedMeeting,
    hasAudio,
    audioUrl:
      hydratedMeeting && hasAudio
        ? `/api/meetings/${hydratedMeeting.id}/audio?t=${hydratedMeeting.audioUpdatedAt?.getTime() || 0}`
        : null,
  });
}

// DELETE /api/meetings/[id] — 删除会议
export async function DELETE(
  _req: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  const { id } = await params;

  await deleteMeetingAudioFile(id);
  await prisma.meeting.delete({ where: { id } });

  return NextResponse.json({ success: true });
}
