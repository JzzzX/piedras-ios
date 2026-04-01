import { NextRequest } from 'next/server';
import { Prisma } from '@prisma/client';
import { requireAuthenticatedRequest } from '@/lib/api-auth';
import { createRequestContext, errorResponse, jsonResponse } from '@/lib/api-error';
import { prisma } from '@/lib/db';
import { deleteMeetingAudioFile, hasMeetingAudioFile } from '@/lib/meeting-audio';
import { deleteMeetingAttachmentsDir } from '@/lib/meeting-attachment';
import { recoverPendingMeetingAudioProcessing } from '@/lib/meeting-audio-processing';
import { serializeMeetingDetail } from '@/lib/meeting-response';

// GET /api/meetings/[id] — 获取单个会议详情
export async function GET(
  req: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  const context = createRequestContext(req, '/api/meetings/[id]');
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
      include: {
        collection: true,
        segments: { orderBy: { order: 'asc' } },
        chatMessages: { orderBy: { timestamp: 'asc' } },
        noteAttachments: { orderBy: { createdAt: 'asc' } },
      },
    });

    if (!meeting) {
      return errorResponse(context, 404, '会议不存在');
    }

    const hasAudio =
      Boolean(meeting.audioMimeType) && (await hasMeetingAudioFile(meeting.id));

    return jsonResponse(context, serializeMeetingDetail(meeting, { hasAudio }));
  } catch (error) {
    return errorResponse(
      context,
      500,
      error instanceof Error ? `加载会议详情失败：${error.message}` : '加载会议详情失败，请稍后重试。',
      error
    );
  }
}

// PUT /api/meetings/[id] — 更新会议
export async function PUT(
  req: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  const context = createRequestContext(req, '/api/meetings/[id]');
  const auth = await requireAuthenticatedRequest(req, context);

  if (auth instanceof Response) {
    return auth;
  }

  try {
    const { id } = await params;
    const body = await req.json();
    const {
      title,
      status,
      duration,
      collectionId,
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
      audioCloudSyncEnabled,
    } = body;
    const existingMeeting = await prisma.meeting.findFirst({
      where: {
        id,
        workspaceId: auth.workspace.id,
      },
      select: { id: true },
    });

    if (!existingMeeting) {
      return errorResponse(context, 404, '会议不存在');
    }

    const updateData: Record<string, unknown> = {};
    if (title !== undefined) updateData.title = title;
    if (status !== undefined) updateData.status = status;
    if (duration !== undefined) updateData.duration = duration;
    if (collectionId !== undefined) updateData.collectionId = collectionId || null;
    updateData.workspaceId = auth.workspace.id;
    if (userNotes !== undefined) updateData.userNotes = userNotes;
    if (enhancedNotes !== undefined) updateData.enhancedNotes = enhancedNotes;
    if (enhanceRecipeId !== undefined) updateData.enhanceRecipeId = enhanceRecipeId || null;
    if (roundLabel !== undefined) updateData.roundLabel = roundLabel;
    if (interviewerName !== undefined) updateData.interviewerName = interviewerName;
    if (recommendation !== undefined) updateData.recommendation = recommendation;
    if (handoffNote !== undefined) updateData.handoffNote = handoffNote;
    if (speakers !== undefined) updateData.speakers = JSON.stringify(speakers);
    if (audioCloudSyncEnabled !== undefined) updateData.audioCloudSyncEnabled = Boolean(audioCloudSyncEnabled);

    const meeting = await prisma.meeting.update({
      where: { id },
      data: updateData,
    });

    if (segments) {
      await prisma.transcriptSegment.deleteMany({ where: { meetingId: id } });
      await prisma.transcriptSegment.createMany({
        data: segments.map(
          (
            s: { id: string; speaker: string; text: string; startTime: number; endTime: number; isFinal: boolean },
            i: number
          ) => ({
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

    if (chatMessages) {
      await prisma.chatMessage.deleteMany({ where: { meetingId: id } });
      await prisma.chatMessage.createMany({
        data: chatMessages.map(
          (
            m: { id: string; role: string; content: string; timestamp: number; recipeId?: string; templateId?: string }
          ) => ({
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
        noteAttachments: { orderBy: { createdAt: 'asc' } },
      },
    });

    const hasAudio =
      Boolean(hydratedMeeting?.audioMimeType) &&
      hydratedMeeting
        ? await hasMeetingAudioFile(hydratedMeeting.id)
        : false;

    return jsonResponse(
      context,
      hydratedMeeting
        ? serializeMeetingDetail(hydratedMeeting, { hasAudio })
        : null
    );
  } catch (error) {
    return errorResponse(
      context,
      500,
      error instanceof Error ? `更新会议失败：${error.message}` : '更新会议失败，请稍后重试。',
      error
    );
  }
}

// DELETE /api/meetings/[id] — 删除会议
export async function DELETE(
  req: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  const context = createRequestContext(req, '/api/meetings/[id]');
  const auth = await requireAuthenticatedRequest(req, context);

  if (auth instanceof Response) {
    return auth;
  }

  try {
    const { id } = await params;

    const existingMeeting = await prisma.meeting.findFirst({
      where: {
        id,
        workspaceId: auth.workspace.id,
      },
      select: { id: true },
    });

    if (!existingMeeting) {
      return jsonResponse(context, { success: true });
    }

    await deleteMeetingAudioFile(id);
    await deleteMeetingAttachmentsDir(id);
    await prisma.meeting.delete({ where: { id } });

    return jsonResponse(context, { success: true });
  } catch (error) {
    if (error instanceof Prisma.PrismaClientKnownRequestError && error.code === 'P2025') {
      return jsonResponse(context, { success: true });
    }

    return errorResponse(
      context,
      500,
      error instanceof Error ? `删除会议失败：${error.message}` : '删除会议失败，请稍后重试。',
      error
    );
  }
}
