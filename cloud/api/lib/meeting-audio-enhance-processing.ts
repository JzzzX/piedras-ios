import { readFile } from 'node:fs/promises';
import { execFile } from 'node:child_process';
import { mkdtemp, rm } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { promisify } from 'node:util';
import type { Meeting } from '@prisma/client';
import { prisma } from './db.ts';
import { generateTextWithFallback, hasAvailableLlm } from './llm-provider.ts';
import { getMeetingAudioPath, hasMeetingAudioFile } from './meeting-audio.ts';
import { buildAudioMeetingMaterialContext } from './meeting-ai-context.ts';
import type { PromptOptions } from './types.ts';
import {
  buildEnhanceSystemPrompt,
  normalizeEnhancePromptOptions,
} from '../app/api/enhance/prompt.ts';

const AUDIO_ENHANCE_TIMEOUT_MS = 25_000;
const AUDIO_ENHANCE_MAX_TOKENS = 1_400;
const INLINE_AUDIO_MAX_BYTES = 18 * 1024 * 1024;
const RECOVERY_INTERVAL_MS = 30_000;
const execFileAsync = promisify(execFile);

export type MeetingAudioEnhanceState = 'idle' | 'processing' | 'ready' | 'failed';

export interface MeetingAudioEnhanceRequestPayload {
  userNotes?: string;
  noteAttachmentsContext?: string;
  segmentCommentsContext?: string;
  promptOptions?: Partial<PromptOptions>;
}

export interface MeetingAudioEnhanceStatus {
  audioEnhancedNotes: string;
  audioEnhancedNotesStatus: MeetingAudioEnhanceState;
  audioEnhancedNotesError: string | null;
  audioEnhancedNotesUpdatedAt: string | null;
  audioEnhancedNotesProvider: string | null;
  audioEnhancedNotesModel: string | null;
  audioEnhancedNotesAttempts: number;
  audioEnhancedNotesRequestedAt: string | null;
  audioEnhancedNotesStartedAt: string | null;
}

type MeetingAudioEnhanceInputStrategy = 'inline_mp3' | 'file_upload';

interface MeetingAudioEnhanceInputStrategyOptions {
  mimeType: string;
  byteLength: number;
  geminiConfigured: boolean;
}

interface QueueMeetingAudioEnhanceOptions {
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

const globalForMeetingAudioEnhance = globalThis as unknown as {
  __piedrasMeetingAudioEnhanceQueue?: RuntimeQueueState;
};

export function createMeetingAudioEnhanceRuntimeState(): RuntimeQueueState {
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
  if (!globalForMeetingAudioEnhance.__piedrasMeetingAudioEnhanceQueue) {
    globalForMeetingAudioEnhance.__piedrasMeetingAudioEnhanceQueue =
      createMeetingAudioEnhanceRuntimeState();
  }

  return globalForMeetingAudioEnhance.__piedrasMeetingAudioEnhanceQueue;
}

function normalizeEnhanceState(value: string | null | undefined): MeetingAudioEnhanceState {
  switch (value) {
    case 'processing':
    case 'ready':
    case 'failed':
      return value;
    default:
      return 'idle';
  }
}

function toISOStringOrNull(value: Date | null | undefined) {
  return value ? value.toISOString() : null;
}

export function buildMeetingAudioEnhanceStatus(
  meeting: Pick<
    Meeting,
    | 'audioEnhancedNotes'
    | 'audioEnhancedNotesStatus'
    | 'audioEnhancedNotesError'
    | 'audioEnhancedNotesUpdatedAt'
    | 'audioEnhancedNotesProvider'
    | 'audioEnhancedNotesModel'
    | 'audioEnhancedNotesAttempts'
    | 'audioEnhancedNotesRequestedAt'
    | 'audioEnhancedNotesStartedAt'
  >
): MeetingAudioEnhanceStatus {
  return {
    audioEnhancedNotes: meeting.audioEnhancedNotes,
    audioEnhancedNotesStatus: normalizeEnhanceState(meeting.audioEnhancedNotesStatus),
    audioEnhancedNotesError: meeting.audioEnhancedNotesError.trim() || null,
    audioEnhancedNotesUpdatedAt: toISOStringOrNull(meeting.audioEnhancedNotesUpdatedAt),
    audioEnhancedNotesProvider: meeting.audioEnhancedNotesProvider?.trim() || null,
    audioEnhancedNotesModel: meeting.audioEnhancedNotesModel?.trim() || null,
    audioEnhancedNotesAttempts: meeting.audioEnhancedNotesAttempts,
    audioEnhancedNotesRequestedAt: toISOStringOrNull(meeting.audioEnhancedNotesRequestedAt),
    audioEnhancedNotesStartedAt: toISOStringOrNull(meeting.audioEnhancedNotesStartedAt),
  };
}

export function resolveMeetingAudioEnhanceInputStrategy(
  options: MeetingAudioEnhanceInputStrategyOptions
): MeetingAudioEnhanceInputStrategy {
  if (options.geminiConfigured && options.byteLength > INLINE_AUDIO_MAX_BYTES) {
    return 'file_upload';
  }

  return 'inline_mp3';
}

export function enqueueMeetingAudioEnhance(runtime: RuntimeQueueState, meetingId: string) {
  if (runtime.queued.has(meetingId) || runtime.active.has(meetingId)) {
    return false;
  }

  runtime.queued.add(meetingId);
  runtime.queue.push(meetingId);
  return true;
}

export function markMeetingAudioEnhanceActive(runtime: RuntimeQueueState, meetingId: string) {
  runtime.active.add(meetingId);
}

export function markMeetingAudioEnhanceIdle(runtime: RuntimeQueueState, meetingId: string) {
  runtime.active.delete(meetingId);
}

function enqueueMeeting(meetingId: string) {
  return enqueueMeetingAudioEnhance(getRuntimeQueueState(), meetingId);
}

async function drainMeetingAudioEnhanceQueue() {
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
      markMeetingAudioEnhanceActive(runtime, meetingId);

      try {
        await processMeetingAudioEnhance(meetingId);
      } catch (error) {
        console.error(
          JSON.stringify({
            scope: 'meeting-audio-enhance-processing',
            event: 'process-failed',
            meetingId,
            error: error instanceof Error ? error.message : String(error),
            timestamp: new Date().toISOString(),
          })
        );
      } finally {
        markMeetingAudioEnhanceIdle(runtime, meetingId);
      }
    }
  } finally {
    runtime.running = false;
  }
}

export async function queueMeetingAudioEnhanceProcessing(options: QueueMeetingAudioEnhanceOptions) {
  enqueueMeeting(options.meetingId);
  console.log(
    JSON.stringify({
      scope: 'meeting-audio-enhance-processing',
      event: 'queued',
      meetingId: options.meetingId,
      requestId: options.requestId,
      timestamp: new Date().toISOString(),
    })
  );
  void drainMeetingAudioEnhanceQueue();
}

export async function recoverPendingMeetingAudioEnhanceProcessing() {
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
      const meetings = await prisma.meeting.findMany({
        where: {
          audioEnhancedNotesStatus: 'processing',
          audioEnhancedNotesRequestPayload: {
            not: null,
          },
        },
        select: {
          id: true,
        },
        orderBy: {
          audioEnhancedNotesRequestedAt: 'asc',
        },
        take: 20,
      });

      for (const meeting of meetings) {
        enqueueMeeting(meeting.id);
      }

      if (meetings.length > 0) {
        void drainMeetingAudioEnhanceQueue();
      }
    } finally {
      runtime.recoveryPromise = null;
    }
  })();

  return runtime.recoveryPromise;
}

export async function persistMeetingAudioEnhanceRequest(
  meetingId: string,
  payload: MeetingAudioEnhanceRequestPayload
) {
  const now = new Date();

  return prisma.meeting.update({
    where: { id: meetingId },
    data: {
      audioEnhancedNotesStatus: 'processing',
      audioEnhancedNotesError: '',
      audioEnhancedNotesRequestPayload: JSON.stringify(payload),
      audioEnhancedNotesRequestedAt: now,
      audioEnhancedNotesStartedAt: null,
      audioEnhancedNotesProvider: null,
      audioEnhancedNotesModel: null,
    },
    select: {
      audioEnhancedNotes: true,
      audioEnhancedNotesStatus: true,
      audioEnhancedNotesError: true,
      audioEnhancedNotesUpdatedAt: true,
      audioEnhancedNotesProvider: true,
      audioEnhancedNotesModel: true,
      audioEnhancedNotesAttempts: true,
      audioEnhancedNotesRequestedAt: true,
      audioEnhancedNotesStartedAt: true,
    },
  });
}

async function processMeetingAudioEnhance(meetingId: string) {
  const meeting = await prisma.meeting.findUnique({
    where: { id: meetingId },
    select: {
      id: true,
      title: true,
      audioMimeType: true,
      audioEnhancedNotesRequestPayload: true,
    },
  });

  if (!meeting) {
    return;
  }

  if (!meeting.audioMimeType || !(await hasMeetingAudioFile(meeting.id))) {
    await markAudioEnhanceFailure(meeting.id, '会议音频不存在，请先完成音频上传。');
    return;
  }

  if (!meeting.audioEnhancedNotesRequestPayload?.trim()) {
    await markAudioEnhanceFailure(meeting.id, '音频 AI 笔记请求参数缺失，请重新发起生成。');
    return;
  }

  const payload = parsePersistedPayload(meeting.audioEnhancedNotesRequestPayload);
  const startedAt = new Date();

  await prisma.meeting.update({
    where: { id: meeting.id },
    data: {
      audioEnhancedNotesStatus: 'processing',
      audioEnhancedNotesError: '',
      audioEnhancedNotesStartedAt: startedAt,
      audioEnhancedNotesAttempts: {
        increment: 1,
      },
    },
  });

  try {
    const result = hasAvailableLlm()
      ? await generateAudioEnhancedNotes(meeting.id, meeting.title || '未命名会议', meeting.audioMimeType, payload)
      : {
          content: generateDemoAudioEnhancedNotes(meeting.title || '未命名会议'),
          provider: 'demo' as const,
          model: null,
        };

    const now = new Date();
    await prisma.meeting.update({
      where: { id: meeting.id },
      data: {
        audioEnhancedNotes: result.content,
        audioEnhancedNotesStatus: 'ready',
        audioEnhancedNotesError: '',
        audioEnhancedNotesUpdatedAt: now,
        audioEnhancedNotesProvider: result.provider,
        audioEnhancedNotesModel: result.model,
        audioEnhancedNotesRequestPayload: null,
      },
    });
  } catch (error) {
    await markAudioEnhanceFailure(
      meeting.id,
      error instanceof Error ? `音频 AI 笔记生成失败：${error.message}` : '音频 AI 笔记生成失败，请稍后重试。'
    );
  }
}

function parsePersistedPayload(rawPayload: string): MeetingAudioEnhanceRequestPayload {
  try {
    const parsed = JSON.parse(rawPayload);
    if (!parsed || typeof parsed !== 'object') {
      return {};
    }
    return parsed as MeetingAudioEnhanceRequestPayload;
  } catch {
    return {};
  }
}

async function generateAudioEnhancedNotes(
  meetingId: string,
  meetingTitle: string,
  mimeType: string,
  payload: MeetingAudioEnhanceRequestPayload
) {
  const options = normalizeEnhancePromptOptions(payload.promptOptions);
  const systemPrompt = `${buildEnhanceSystemPrompt(options)}\n\n你将收到会议原始音频以及补充上下文。必须优先依据原始音频内容归纳会议，不要把缺失信息硬补成结论。`;
  const audioPart = await buildAudioContentPart({
    meetingId,
    mimeType,
    requestId: `audio-ai-notes:${meetingId}`,
  });
  const contextText = buildAudioMeetingMaterialContext({
    userNotes: payload.userNotes,
    noteAttachmentsContext: payload.noteAttachmentsContext,
    segmentCommentsContext: payload.segmentCommentsContext,
  });

  const { content, provider } = await generateTextWithFallback({
    messages: [
      { role: 'system', content: systemPrompt },
      {
        role: 'user',
        content: [
          {
            type: 'text',
            text: `会议标题：${meetingTitle}\n\n以下是用户补充上下文：\n${contextText}\n\n请根据原始音频和补充上下文输出结构化会议纪要。`,
          },
          audioPart,
        ],
      },
    ],
    temperature: 0.2,
    maxTokens: AUDIO_ENHANCE_MAX_TOKENS,
    timeoutMs: AUDIO_ENHANCE_TIMEOUT_MS,
    retries: 0,
    preferredProvider: 'openai',
    allowedProviders: ['openai', 'gemini'],
  });

  return {
    content,
    provider,
    model: resolveAudioEnhanceModel(provider),
  };
}

async function buildAudioContentPart({
  meetingId,
  mimeType,
  requestId,
}: {
  meetingId: string;
  mimeType: string;
  requestId: string;
}) {
  const preparedAudio = await prepareAudioForMeetingEnhance(getMeetingAudioPath(meetingId));
  try {
    const strategy = resolveMeetingAudioEnhanceInputStrategy({
      mimeType,
      byteLength: preparedAudio.byteLength,
      geminiConfigured: Boolean(process.env.GEMINI_API_KEY),
    });

    if (strategy === 'inline_mp3') {
      return {
        type: 'audio' as const,
        mimeType: 'audio/mpeg',
        data: (await readFile(preparedAudio.outputPath)).toString('base64'),
      };
    }

    const uploadMimeType = 'audio/mpeg';
    const fileUri = await uploadGeminiAudioFile({
      buffer: await readFile(preparedAudio.outputPath),
      mimeType: uploadMimeType,
      displayName: `meeting-${meetingId}-${requestId}`,
    });

    return {
      type: 'file_audio' as const,
      mimeType: uploadMimeType,
      fileUri,
    };
  } finally {
    await preparedAudio.cleanup();
  }
}

async function prepareAudioForMeetingEnhance(inputPath: string) {
  const tempDir = await mkdtemp(path.join(os.tmpdir(), 'piedras-audio-enhance-'));
  const outputPath = path.join(tempDir, 'meeting-upload.mp3');

  try {
    await execFileAsync('ffmpeg', [
      '-y',
      '-i',
      inputPath,
      '-vn',
      '-ac',
      '1',
      '-ar',
      '16000',
      '-c:a',
      'libmp3lame',
      '-b:a',
      '64k',
      outputPath,
    ]);

    const outputBuffer = await readFile(outputPath);
    return {
      outputPath,
      byteLength: outputBuffer.byteLength,
      cleanup: async () => {
        await rm(tempDir, { recursive: true, force: true });
      },
    };
  } catch (error) {
    await rm(tempDir, { recursive: true, force: true });
    const detail = error instanceof Error ? error.message : String(error);
    throw new Error(`音频 AI 笔记转码失败：${detail}`);
  }
}

async function uploadGeminiAudioFile({
  buffer,
  mimeType,
  displayName,
}: {
  buffer: Buffer;
  mimeType: string;
  displayName: string;
}): Promise<string> {
  const apiKey = process.env.GEMINI_API_KEY;
  if (!apiKey) {
    throw new Error('GEMINI_API_KEY 未配置');
  }

  const startResponse = await fetch('https://generativelanguage.googleapis.com/upload/v1beta/files', {
    method: 'POST',
    headers: {
      'x-goog-api-key': apiKey,
      'X-Goog-Upload-Protocol': 'resumable',
      'X-Goog-Upload-Command': 'start',
      'X-Goog-Upload-Header-Content-Length': String(buffer.byteLength),
      'X-Goog-Upload-Header-Content-Type': mimeType,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      file: {
        display_name: displayName,
      },
    }),
  });

  if (!startResponse.ok) {
    throw new Error(`Gemini 文件上传初始化失败（HTTP ${startResponse.status}）`);
  }

  const uploadUrl = startResponse.headers.get('x-goog-upload-url');
  if (!uploadUrl) {
    throw new Error('Gemini 文件上传初始化失败：未返回上传地址');
  }

  const uploadResponse = await fetch(uploadUrl, {
    method: 'POST',
    headers: {
      'Content-Length': String(buffer.byteLength),
      'X-Goog-Upload-Offset': '0',
      'X-Goog-Upload-Command': 'upload, finalize',
    },
    body: new Uint8Array(buffer),
  });

  if (!uploadResponse.ok) {
    throw new Error(`Gemini 文件上传失败（HTTP ${uploadResponse.status}）`);
  }

  const payload = await uploadResponse.json();
  const fileUri = payload?.file?.uri;
  if (typeof fileUri !== 'string' || !fileUri.trim()) {
    throw new Error('Gemini 文件上传失败：未返回 file uri');
  }

  return fileUri;
}

async function markAudioEnhanceFailure(meetingId: string, message: string) {
  await prisma.meeting.update({
    where: { id: meetingId },
    data: {
      audioEnhancedNotesStatus: 'failed',
      audioEnhancedNotesError: message,
      audioEnhancedNotesRequestPayload: null,
      audioEnhancedNotesProvider: null,
      audioEnhancedNotesModel: null,
    },
  });
}

function resolveAudioEnhanceModel(provider: 'gemini' | 'minimax' | 'openai' | 'demo') {
  if (provider === 'gemini') {
    return process.env.GEMINI_MODEL || 'gemini-3-flash-preview';
  }
  if (provider === 'openai') {
    return process.env.OPENAI_MODEL || null;
  }
  return null;
}

function generateDemoAudioEnhancedNotes(meetingTitle: string): string {
  return `## 会议摘要
本次「${meetingTitle}」的音频版 AI 笔记处于 Demo 模式，当前结果仅用于验证多模态链路。

## 关键讨论点
- 原始音频总结链路已触发
- 请配置可用的 LLM 凭据后再查看真实总结

## 待确认事项
- 当前为实验能力，默认不对正式笔记产生影响`;
}
