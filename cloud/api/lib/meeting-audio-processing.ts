import { randomUUID } from 'node:crypto';
import type { Meeting } from '@prisma/client';
import { prisma } from './db.ts';
import { getMeetingAudioPath, hasMeetingAudioFile } from './meeting-audio.ts';
import {
  finalizeMeetingTranscriptFromAudio,
  isEmptyTranscriptFinalizationFailure,
} from './meeting-transcript-finalizer.ts';

export type MeetingAudioProcessingState = 'idle' | 'queued' | 'processing' | 'completed' | 'failed';

export interface MeetingAudioProcessingStatus {
  audioProcessingState: MeetingAudioProcessingState;
  audioProcessingError: string | null;
  audioProcessingAttempts: number;
  audioProcessingRequestedAt: string | null;
  audioProcessingStartedAt: string | null;
  audioProcessingCompletedAt: string | null;
}

interface QueueAudioProcessingOptions {
  meetingId: string;
  requestId: string;
}

interface RuntimeQueueState {
  queue: string[];
  queued: Set<string>;
  active: Set<string>;
  running: boolean;
  lastRecoveryAt: number;
  recoveryPromise: Promise<void> | null;
}

const RECOVERY_INTERVAL_MS = 30_000;

const globalForMeetingAudioProcessing = globalThis as unknown as {
  __piedrasMeetingAudioProcessingQueue?: RuntimeQueueState;
};

export function createMeetingAudioProcessingRuntimeState(): RuntimeQueueState {
  return {
    queue: [],
    queued: new Set<string>(),
    active: new Set<string>(),
    running: false,
    lastRecoveryAt: 0,
    recoveryPromise: null,
  };
}

function getRuntimeQueueState(): RuntimeQueueState {
  if (!globalForMeetingAudioProcessing.__piedrasMeetingAudioProcessingQueue) {
    globalForMeetingAudioProcessing.__piedrasMeetingAudioProcessingQueue =
      createMeetingAudioProcessingRuntimeState();
  }

  return globalForMeetingAudioProcessing.__piedrasMeetingAudioProcessingQueue;
}

function normalizeProcessingState(value: string | null | undefined): MeetingAudioProcessingState {
  switch (value) {
    case 'queued':
    case 'processing':
    case 'completed':
    case 'failed':
      return value;
    default:
      return 'idle';
  }
}

function toISOStringOrNull(value: Date | null | undefined) {
  return value ? value.toISOString() : null;
}

export function buildMeetingAudioProcessingStatus(
  meeting: Pick<
    Meeting,
    | 'audioProcessingState'
    | 'audioProcessingError'
    | 'audioProcessingAttempts'
    | 'audioProcessingRequestedAt'
    | 'audioProcessingStartedAt'
    | 'audioProcessingCompletedAt'
  >
): MeetingAudioProcessingStatus {
  return {
    audioProcessingState: normalizeProcessingState(meeting.audioProcessingState),
    audioProcessingError: meeting.audioProcessingError.trim() || null,
    audioProcessingAttempts: meeting.audioProcessingAttempts,
    audioProcessingRequestedAt: toISOStringOrNull(meeting.audioProcessingRequestedAt),
    audioProcessingStartedAt: toISOStringOrNull(meeting.audioProcessingStartedAt),
    audioProcessingCompletedAt: toISOStringOrNull(meeting.audioProcessingCompletedAt),
  };
}

export function enqueueMeetingForProcessing(runtime: RuntimeQueueState, meetingId: string) {
  if (runtime.queued.has(meetingId) || runtime.active.has(meetingId)) {
    return false;
  }

  runtime.queued.add(meetingId);
  runtime.queue.push(meetingId);
  return true;
}

export function markMeetingAudioProcessingActive(runtime: RuntimeQueueState, meetingId: string) {
  runtime.active.add(meetingId);
}

export function markMeetingAudioProcessingIdle(runtime: RuntimeQueueState, meetingId: string) {
  runtime.active.delete(meetingId);
}

function enqueueMeeting(meetingId: string) {
  const runtime = getRuntimeQueueState();
  return enqueueMeetingForProcessing(runtime, meetingId);
}

async function drainMeetingAudioQueue() {
  const runtime = getRuntimeQueueState();

  if (runtime.running) {
    return;
  }

  runtime.running = true;

  try {
    while (runtime.queue.length > 0) {
      const meetingId = runtime.queue.shift();
      if (!meetingId) {
        continue;
      }

      runtime.queued.delete(meetingId);
      markMeetingAudioProcessingActive(runtime, meetingId);

      try {
        await processMeetingAudioFinalization(meetingId);
      } catch (error) {
        console.error(
          JSON.stringify({
            scope: 'meeting-audio-processing',
            event: 'process-failed',
            meetingId,
            error: error instanceof Error ? error.message : String(error),
            timestamp: new Date().toISOString(),
          })
        );
      } finally {
        markMeetingAudioProcessingIdle(runtime, meetingId);
      }
    }
  } finally {
    runtime.running = false;
  }
}

export async function queueMeetingAudioProcessing(options: QueueAudioProcessingOptions) {
  enqueueMeeting(options.meetingId);
  console.log(
    JSON.stringify({
      scope: 'meeting-audio-processing',
      event: 'queued',
      meetingId: options.meetingId,
      requestId: options.requestId,
      timestamp: new Date().toISOString(),
    })
  );
  void drainMeetingAudioQueue();
}

export async function recoverPendingMeetingAudioProcessing() {
  const runtime = getRuntimeQueueState();
  const now = Date.now();

  if (runtime.recoveryPromise) {
    return runtime.recoveryPromise;
  }

  if (now - runtime.lastRecoveryAt < RECOVERY_INTERVAL_MS) {
    return;
  }

  runtime.lastRecoveryAt = now;
  runtime.recoveryPromise = (async () => {
    try {
      const pendingMeetings = await prisma.meeting.findMany({
        where: {
          audioProcessingState: {
            in: ['queued', 'processing'],
          },
        },
        select: {
          id: true,
        },
        orderBy: {
          audioProcessingRequestedAt: 'asc',
        },
        take: 20,
      });

      for (const meeting of pendingMeetings) {
        enqueueMeeting(meeting.id);
      }

      if (pendingMeetings.length > 0) {
        void drainMeetingAudioQueue();
      }
    } finally {
      runtime.recoveryPromise = null;
    }
  })();

  return runtime.recoveryPromise;
}

async function processMeetingAudioFinalization(meetingId: string) {
  const meeting = await prisma.meeting.findUnique({
    where: { id: meetingId },
    select: {
      id: true,
      audioMimeType: true,
      audioDuration: true,
      audioProcessingState: true,
    },
  });

  if (!meeting) {
    return;
  }

  if (!(await hasMeetingAudioFile(meetingId))) {
    await prisma.meeting.update({
      where: { id: meetingId },
      data: {
        audioProcessingState: 'failed',
        audioProcessingError: '会议音频文件不存在，无法补转写。',
        audioProcessingCompletedAt: new Date(),
      },
    });
    return;
  }

  const startedAt = new Date();

  await prisma.meeting.update({
    where: { id: meetingId },
    data: {
      audioProcessingState: 'processing',
      audioProcessingError: '',
      audioProcessingStartedAt: startedAt,
      audioProcessingAttempts: {
        increment: 1,
      },
    },
  });

  try {
    let finalizedTranscript = null;

    try {
      finalizedTranscript = await finalizeMeetingTranscriptFromAudio({
        audioPath: getMeetingAudioPath(meetingId),
        mimeType: meeting.audioMimeType || 'audio/webm',
        requestId: `audio-processing:${meetingId}`,
        userId: `meeting-${meetingId}`,
      });
    } catch (error) {
      if (!isEmptyTranscriptFinalizationFailure(error)) {
        throw error;
      }
    }

    await prisma.$transaction(async (tx) => {
      await tx.meeting.update({
        where: { id: meetingId },
        data: {
          speakers: JSON.stringify(finalizedTranscript?.speakers ?? {}),
          audioProcessingState: 'completed',
          audioProcessingError: '',
          audioProcessingCompletedAt: new Date(),
        },
      });

      await tx.transcriptSegment.deleteMany({
        where: { meetingId },
      });

      if (finalizedTranscript && finalizedTranscript.segments.length > 0) {
        await tx.transcriptSegment.createMany({
          data: finalizedTranscript.segments.map((segment, index) => ({
            id: randomUUID(),
            meetingId,
            speaker: segment.speaker,
            text: segment.text,
            startTime: segment.startTime,
            endTime: segment.endTime,
            isFinal: segment.isFinal,
            order: index,
          })),
        });
      }
    });
  } catch (error) {
    await prisma.meeting.update({
      where: { id: meetingId },
      data: {
        audioProcessingState: 'failed',
        audioProcessingError: error instanceof Error ? error.message : String(error),
        audioProcessingCompletedAt: new Date(),
      },
    });
  }
}
