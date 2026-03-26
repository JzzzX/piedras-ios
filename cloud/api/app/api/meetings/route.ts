import { NextRequest } from 'next/server';
import { requireAuthenticatedRequest } from '@/lib/api-auth';
import { createRequestContext, errorResponse, jsonResponse } from '@/lib/api-error';
import { prisma } from '@/lib/db';

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
        title: true,
        date: true,
        status: true,
        duration: true,
        audioMimeType: true,
        audioDuration: true,
        audioUpdatedAt: true,
        userNotes: true,
        enhancedNotes: true,
        roundLabel: true,
        interviewerName: true,
        recommendation: true,
        handoffNote: true,
        createdAt: true,
        collectionId: true,
        workspaceId: true,
        collection: {
          select: {
            id: true,
            name: true,
            description: true,
            icon: true,
            color: true,
            sortOrder: true,
            workspaceId: true,
            createdAt: true,
            updatedAt: true,
          },
        },
        workspace: {
          select: {
            id: true,
            name: true,
            icon: true,
            color: true,
          },
        },
        _count: { select: { segments: true, chatMessages: true } },
      },
    });

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
    } = body;

    const normalizedDate = date ? new Date(date) : new Date();
    const normalizedSegments = (segments || []) as SegmentPayload[];
    const normalizedChatMessages = (chatMessages || []) as ChatMessagePayload[];
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

      const meetingData = {
        title: title || '',
        date: normalizedDate,
        status: status || 'ended',
        duration: duration || 0,
        collectionId: collectionId || null,
        workspaceId: auth.workspace.id,
        userNotes: userNotes || '',
        enhancedNotes: enhancedNotes || '',
        enhanceRecipeId: enhanceRecipeId || null,
        roundLabel: roundLabel || '',
        interviewerName: interviewerName || '',
        recommendation: recommendation || 'pending',
        handoffNote: handoffNote || '',
        speakers: JSON.stringify(speakers || {}),
      };

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

      await tx.chatMessage.deleteMany({
        where: { meetingId: upsertedMeeting.id },
      });

      if (normalizedChatMessages.length > 0) {
        await tx.chatMessage.createMany({
          data: normalizedChatMessages.map((m) => ({
            id: m.id,
            meetingId: upsertedMeeting.id,
            role: m.role,
            content: m.content,
            timestamp: m.timestamp,
            templateId: m.recipeId || m.templateId || null,
          })),
        });
      }

      return tx.meeting.findUnique({
        where: { id: upsertedMeeting.id },
        include: {
          collection: true,
          segments: { orderBy: { order: 'asc' } },
          chatMessages: { orderBy: { timestamp: 'asc' } },
        },
      });
    });

    return jsonResponse(context, {
      ...meeting,
      speakers: meeting ? JSON.parse(meeting.speakers) : {},
    });
  } catch (error) {
    return errorResponse(
      context,
      500,
      error instanceof Error ? `保存会议失败：${error.message}` : '保存会议失败，请稍后重试。',
      error
    );
  }
}
