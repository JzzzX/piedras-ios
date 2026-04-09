import { NextRequest } from 'next/server';
import { Prisma } from '@prisma/client';
import { requireAuthenticatedRequest } from '@/lib/api-auth';
import { createRequestContext, errorResponse, jsonResponse } from '@/lib/api-error';
import { prisma } from '@/lib/db';
import { deleteMeetingAudioFile, hasMeetingAudioFile } from '@/lib/meeting-audio';
import {
  deleteMeetingAttachmentsDir,
  partitionMeetingAttachmentsByFile,
} from '@/lib/meeting-attachment';
import { purgeExpiredTrashedMeetings } from '@/lib/meeting-trash';
import { recoverPendingMeetingAudioProcessing } from '@/lib/meeting-audio-processing';
import { serializeMeetingDetail } from '@/lib/meeting-response';
import { requireStartupBootstrapReady } from '@/lib/startup-bootstrap-guard';

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

  const startupGuard = requireStartupBootstrapReady(context);
  if (startupGuard) {
    return startupGuard;
  }

  try {
    await purgeExpiredTrashedMeetings(prisma, {
      deleteMeetingAudio: deleteMeetingAudioFile,
      deleteMeetingAttachments: deleteMeetingAttachmentsDir,
    });

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
    const availableNoteAttachments = await sanitizeMeetingNoteAttachments(
      meeting.id,
      meeting.noteAttachments ?? []
    );

    const payload = serializeMeetingDetail(
      {
        ...meeting,
        noteAttachments: availableNoteAttachments,
      },
      { hasAudio }
    );
    console.log(
      JSON.stringify({
        scope: 'cloud-sync',
        event: 'meeting_detail_loaded',
        route: context.route,
        requestId: context.requestId,
        workspaceId: auth.workspace.id,
        meetingId: meeting.id,
        hasAudio,
        noteAttachmentCount: payload.noteAttachments.length,
        audioCloudSyncEnabled: payload.audioCloudSyncEnabled,
      })
    );

    return jsonResponse(context, payload);
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

  const startupGuard = requireStartupBootstrapReady(context);
  if (startupGuard) {
    return startupGuard;
  }

  try {
    const { id } = await params;
    const body = await req.json();
    const {
      title,
      status,
      duration,
      collectionId,
      previousCollectionId,
      deletedAt,
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
    if (previousCollectionId !== undefined) updateData.previousCollectionId = previousCollectionId || null;
    if (deletedAt !== undefined) updateData.deletedAt = deletedAt ? new Date(deletedAt) : null;
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

    if (Array.isArray(segments)) {
      await prisma.transcriptSegment.deleteMany({ where: { meetingId: id } });
      if (segments.length > 0) {
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
    }

    if (Array.isArray(chatMessages)) {
      await mergeMeetingChatMessages(prisma, id, chatMessages);
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
    const availableNoteAttachments = hydratedMeeting
      ? await sanitizeMeetingNoteAttachments(hydratedMeeting.id, hydratedMeeting.noteAttachments ?? [])
      : [];

    const payload = hydratedMeeting
      ? serializeMeetingDetail(
          {
            ...hydratedMeeting,
            noteAttachments: availableNoteAttachments,
          },
          { hasAudio }
        )
      : null;

    if (payload) {
      console.log(
        JSON.stringify({
          scope: 'cloud-sync',
          event: 'meeting_updated',
          route: context.route,
          requestId: context.requestId,
          workspaceId: auth.workspace.id,
          meetingId: payload.id,
          segmentCount: Array.isArray(segments) ? segments.length : null,
          chatMessageCount: Array.isArray(chatMessages) ? chatMessages.length : null,
          audioCloudSyncEnabled: payload.audioCloudSyncEnabled ?? true,
        })
      );
    }

    return jsonResponse(
      context,
      payload
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

async function sanitizeMeetingNoteAttachments<T extends { id: string }>(
  meetingId: string,
  attachments: readonly T[]
) {
  const { available, missing } = await partitionMeetingAttachmentsByFile(meetingId, attachments);

  if (missing.length > 0) {
    await prisma.meetingAttachment.deleteMany({
      where: {
        meetingId,
        id: {
          in: missing.map((attachment) => attachment.id),
        },
      },
    });
  }

  return available;
}

async function mergeMeetingChatMessages(
  client: typeof prisma,
  meetingId: string,
  chatMessages: Array<{
    id: string;
    role: string;
    content: string;
    timestamp: number;
    recipeId?: string;
    templateId?: string;
  }>
) {
  for (const message of chatMessages) {
    await client.chatMessage.upsert({
      where: { id: message.id },
      update: {
        role: message.role,
        content: message.content,
        timestamp: message.timestamp,
        templateId: message.recipeId || message.templateId || null,
      },
      create: {
        id: message.id,
        meetingId,
        role: message.role,
        content: message.content,
        timestamp: message.timestamp,
        templateId: message.recipeId || message.templateId || null,
      },
    });
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

  const startupGuard = requireStartupBootstrapReady(context);
  if (startupGuard) {
    return startupGuard;
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

    console.log(
      JSON.stringify({
        scope: 'cloud-sync',
        event: 'meeting_deleted',
        route: context.route,
        requestId: context.requestId,
        workspaceId: auth.workspace.id,
        meetingId: id,
      })
    );

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
