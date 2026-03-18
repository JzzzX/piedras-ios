import { NextRequest, NextResponse } from 'next/server';
import { prisma } from '@/lib/db';
import { Prisma } from '@prisma/client';
import { resolveWorkspaceId } from '@/lib/default-workspace';

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
  const { searchParams } = new URL(req.url);
  const query = searchParams.get('query')?.trim() || '';
  const dateFrom = searchParams.get('dateFrom');
  const dateTo = searchParams.get('dateTo');
  const collectionId = searchParams.get('collectionId');
  const workspaceId = searchParams.get('workspaceId');

  const where: Prisma.MeetingWhereInput = {};

  if (workspaceId) {
    where.workspaceId = workspaceId;
  }

  if (query) {
    where.OR = [
      { title: { contains: query } },
      { enhancedNotes: { contains: query } },
    ];
  }

  if (dateFrom || dateTo) {
    where.date = {};
    if (dateFrom) {
      where.date.gte = new Date(`${dateFrom}T00:00:00`);
    }
    if (dateTo) {
      where.date.lte = new Date(`${dateTo}T23:59:59.999`);
    }
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
  return NextResponse.json(meetings);
}

// POST /api/meetings — 创建或保存会议
export async function POST(req: NextRequest) {
  const body = await req.json();
  const {
    id,
    title,
    date,
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

  const normalizedDate = date ? new Date(date) : new Date();
  const normalizedSegments = (segments || []) as SegmentPayload[];
  const normalizedChatMessages = (chatMessages || []) as ChatMessagePayload[];
  const resolvedWorkspaceId = await resolveWorkspaceId(workspaceId);

  // 每次保存都以最新状态覆盖 segments/chat，避免增量保存时出现旧数据
  const meeting = await prisma.$transaction(async (tx) => {
    const upsertedMeeting = await tx.meeting.upsert({
      where: { id: id || '' },
      create: {
        id: id || undefined,
        title: title || '',
        date: normalizedDate,
        status: status || 'ended',
        duration: duration || 0,
        collectionId: collectionId || null,
        workspaceId: resolvedWorkspaceId,
        userNotes: userNotes || '',
        enhancedNotes: enhancedNotes || '',
        enhanceRecipeId: enhanceRecipeId || null,
        roundLabel: roundLabel || '',
        interviewerName: interviewerName || '',
        recommendation: recommendation || 'pending',
        handoffNote: handoffNote || '',
        speakers: JSON.stringify(speakers || {}),
      },
      update: {
        title: title || '',
        date: normalizedDate,
        status: status || 'ended',
        duration: duration || 0,
        collectionId: collectionId || null,
        workspaceId: resolvedWorkspaceId,
        userNotes: userNotes || '',
        enhancedNotes: enhancedNotes || '',
        enhanceRecipeId: enhanceRecipeId || null,
        roundLabel: roundLabel || '',
        interviewerName: interviewerName || '',
        recommendation: recommendation || 'pending',
        handoffNote: handoffNote || '',
        speakers: JSON.stringify(speakers || {}),
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

  return NextResponse.json(meeting);
}
