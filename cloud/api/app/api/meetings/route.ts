import { NextRequest } from 'next/server';
import { requireAuthenticatedRequest } from '@/lib/api-auth';
import { createRequestContext, errorResponse, jsonResponse } from '@/lib/api-error';
import { prisma } from '@/lib/db';
import { hasMeetingAudioFile } from '@/lib/meeting-audio';
import { serializeMeetingDetail } from '@/lib/meeting-response';
import { requireStartupBootstrapReady } from '@/lib/startup-bootstrap-guard';
import { ensureDefaultCollectionForWorkspace } from '@/lib/user-collection-db';

interface SegmentPayload {
  id: string;
  speaker: string;
  text: string;
  startTime: number;
  endTime: number;
  isFinal: boolean;
}

interface ChatMessagePayload {
  id: string;
  role: string;
  content: string;
  timestamp: number;
  recipeId?: string;
  templateId?: string;
}

// GET /api/meetings — 获取会议列表
export async function GET(req: NextRequest) {
  const context = createRequestContext(req, '/api/meetings');
  const auth = await requireAuthenticatedRequest(req, context);

  if (auth instanceof Response) {
    return auth;
  }

  const startupGuard = requireStartupBootstrapReady(context);
  if (startupGuard) {
    return startupGuard;
  }

  try {
    const { searchParams } = new URL(req.url);
    const query = searchParams.get('query')?.trim() || '';
    const dateFrom = searchParams.get('dateFrom');
    const dateTo = searchParams.get('dateTo');
    const collectionId = searchParams.get('collectionId');
    const where: Record<string, unknown> = {
      workspaceId: auth.workspace.id,
    };

    if (query) {
      where.OR = [
        { title: { contains: query } },
        { enhancedNotes: { contains: query } },
      ];
    }

    if (dateFrom || dateTo) {
      const dateFilter: { gte?: Date; lte?: Date } = {};
      if (dateFrom) {
        dateFilter.gte = new Date(`${dateFrom}T00:00:00`);
      }
      if (dateTo) {
        dateFilter.lte = new Date(`${dateTo}T23:59:59.999`);
      }
      where.date = dateFilter;
    }

    if (collectionId) {
      where.collectionId = collectionId === '__ungrouped' ? null : collectionId;
    }

    const meetings = await prisma.meeting.findMany({
      where,
      orderBy: { date: 'desc' },
      select: {
        id: true,
        updatedAt: true,
        audioUpdatedAt: true,
        audioProcessingState: true,
      },
    });

    console.log(
      JSON.stringify({
        scope: 'cloud-sync',
        event: 'meetings_list_loaded',
        route: context.route,
        requestId: context.requestId,
        workspaceId: auth.workspace.id,
        meetingCount: meetings.length,
        query,
        collectionId: collectionId || null,
      })
    );

    return jsonResponse(context, meetings);
  } catch (error) {
    if (error instanceof Error && error.message === '当前账号无权修改该会议') {
      return errorResponse(context, 403, error.message, error);
    }

    return errorResponse(
      context,
      500,
      error instanceof Error ? `加载会议列表失败：${error.message}` : '加载会议列表失败，请稍后重试。',
      error
    );
  }
}

// POST /api/meetings — 创建或保存会议
export async function POST(req: NextRequest) {
  const context = createRequestContext(req, '/api/meetings');
  const auth = await requireAuthenticatedRequest(req, context);

  if (auth instanceof Response) {
    return auth;
  }

  const startupGuard = requireStartupBootstrapReady(context);
  if (startupGuard) {
    return startupGuard;
  }

  try {
    const body = await req.json();
    const {
      id,
      title,
      date,
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

    const normalizedDate = date ? new Date(date) : new Date();
    const normalizedSegments = Array.isArray(segments) ? (segments as SegmentPayload[]) : null;
    const normalizedChatMessages = Array.isArray(chatMessages)
      ? (chatMessages as ChatMessagePayload[])
      : null;
    const fallbackCollection = collectionId
      ? null
      : await ensureDefaultCollectionForWorkspace(prisma, {
          workspaceId: auth.workspace.id,
        });
    const meeting = await prisma.$transaction(async (tx: any) => {
      const existingMeeting = id
        ? await tx.meeting.findUnique({
            where: { id },
            select: { id: true, workspaceId: true },
          })
        : null;

      if (existingMeeting && existingMeeting.workspaceId !== auth.workspace.id) {
        throw new Error('当前账号无权修改该会议');
      }

      const meetingData: Record<string, unknown> = {
        title: title || '',
        date: normalizedDate,
        status: status || 'ended',
        duration: duration || 0,
        collectionId: collectionId || fallbackCollection?.id || null,
        workspaceId: auth.workspace.id,
        userNotes: userNotes || '',
        enhancedNotes: enhancedNotes || '',
        enhanceRecipeId: enhanceRecipeId || null,
        roundLabel: roundLabel || '',
        interviewerName: interviewerName || '',
        recommendation: recommendation || 'pending',
        handoffNote: handoffNote || '',
        audioCloudSyncEnabled:
          audioCloudSyncEnabled === undefined ? true : Boolean(audioCloudSyncEnabled),
      };
      if (speakers !== undefined) {
        meetingData.speakers = JSON.stringify(speakers || {});
      }

      const upsertedMeeting = existingMeeting
        ? await tx.meeting.update({
            where: { id: existingMeeting.id },
            data: meetingData,
          })
        : await tx.meeting.create({
            data: {
              id: id || undefined,
              ...meetingData,
            },
          });

      if (normalizedSegments) {
        await tx.transcriptSegment.deleteMany({
          where: { meetingId: upsertedMeeting.id },
        });

        if (normalizedSegments.length > 0) {
          await tx.transcriptSegment.createMany({
            data: normalizedSegments.map((s, i) => ({
              id: s.id,
              meetingId: upsertedMeeting.id,
              speaker: s.speaker,
              text: s.text,
              startTime: s.startTime,
              endTime: s.endTime,
              isFinal: s.isFinal,
              order: i,
            })),
          });
        }
      }

      if (normalizedChatMessages) {
        await mergeMeetingChatMessages(tx, upsertedMeeting.id, normalizedChatMessages);
      }

      return tx.meeting.findUnique({
        where: { id: upsertedMeeting.id },
        include: {
          collection: true,
          segments: { orderBy: { order: 'asc' } },
          chatMessages: { orderBy: { timestamp: 'asc' } },
          noteAttachments: { orderBy: { createdAt: 'asc' } },
        },
      });
    });

    const hasAudio = meeting?.audioMimeType ? await hasMeetingAudioFile(meeting.id) : false;

    const payload = meeting ? serializeMeetingDetail(meeting, { hasAudio }) : null;

    if (payload) {
      console.log(
        JSON.stringify({
          scope: 'cloud-sync',
          event: 'meeting_upserted',
          route: context.route,
          requestId: context.requestId,
          workspaceId: auth.workspace.id,
          meetingId: payload.id,
          segmentCount: normalizedSegments?.length ?? null,
          chatMessageCount: normalizedChatMessages?.length ?? null,
          audioCloudSyncEnabled: payload.audioCloudSyncEnabled ?? true,
        })
      );
    }

    return jsonResponse(context, payload);
  } catch (error) {
    return errorResponse(
      context,
      500,
      error instanceof Error ? `保存会议失败：${error.message}` : '保存会议失败，请稍后重试。',
      error
    );
  }
}

async function mergeMeetingChatMessages(
  tx: any,
  meetingId: string,
  chatMessages: ChatMessagePayload[]
) {
  for (const message of chatMessages) {
    await tx.chatMessage.upsert({
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
