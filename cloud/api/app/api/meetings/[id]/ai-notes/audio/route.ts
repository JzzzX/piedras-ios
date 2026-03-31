import { readFile } from 'node:fs/promises';
import { NextRequest } from 'next/server';
import { requireAuthenticatedRequest } from '@/lib/api-auth';
import { createRequestContext, errorResponse, jsonResponse } from '@/lib/api-error';
import { prisma } from '@/lib/db';
import { generateTextWithFallback, hasAvailableLlm } from '@/lib/llm-provider';
import { getMeetingAudioPath, hasMeetingAudioFile } from '@/lib/meeting-audio';
import { buildAudioMeetingMaterialContext } from '@/lib/meeting-ai-context';
import {
  buildEnhanceSystemPrompt,
  normalizeEnhancePromptOptions,
} from '@/app/api/enhance/prompt';

const AUDIO_ENHANCE_TIMEOUT_MS = 25_000;
const AUDIO_ENHANCE_MAX_TOKENS = 1_400;
const INLINE_AUDIO_MAX_BYTES = 18 * 1024 * 1024;

export const runtime = 'nodejs';

export async function POST(
  req: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  const context = createRequestContext(req, '/api/meetings/[id]/ai-notes/audio');
  const auth = await requireAuthenticatedRequest(req, context);

  if (auth instanceof Response) {
    return auth;
  }

  let meetingId = '';

  try {
    const resolvedParams = await params;
    meetingId = resolvedParams.id;

    const meeting = await prisma.meeting.findFirst({
      where: {
        id: meetingId,
        workspaceId: auth.workspace.id,
      },
      select: {
        id: true,
        title: true,
        audioMimeType: true,
      },
    });

    if (!meeting) {
      return errorResponse(context, 404, '会议不存在');
    }

    if (!meeting.audioMimeType || !(await hasMeetingAudioFile(meeting.id))) {
      await markAudioEnhanceFailure(meeting.id, '会议音频不存在，请先完成音频上传。');
      return errorResponse(context, 409, '会议音频不存在，请先完成音频上传。');
    }

    const {
      userNotes,
      noteAttachmentsContext,
      segmentCommentsContext,
      promptOptions,
    } = await req.json();

    if (!hasAvailableLlm()) {
      const content = generateDemoAudioEnhancedNotes(meeting.title || '未命名会议');
      const now = new Date();
      await prisma.meeting.update({
        where: { id: meeting.id },
        data: {
          audioEnhancedNotes: content,
          audioEnhancedNotesStatus: 'ready',
          audioEnhancedNotesError: '',
          audioEnhancedNotesUpdatedAt: now,
          audioEnhancedNotesProvider: 'demo',
          audioEnhancedNotesModel: null,
        },
      });

      return jsonResponse(context, {
        content,
        provider: 'demo',
        status: 'ready',
        updatedAt: now.toISOString(),
      });
    }

    await prisma.meeting.update({
      where: { id: meeting.id },
      data: {
        audioEnhancedNotesStatus: 'processing',
        audioEnhancedNotesError: '',
      },
    });

    const options = normalizeEnhancePromptOptions(promptOptions);
    const systemPrompt = `${buildEnhanceSystemPrompt(options)}\n\n你将收到会议原始音频以及补充上下文。必须优先依据原始音频内容归纳会议，不要把缺失信息硬补成结论。`;
    const audioPart = await buildAudioContentPart({
      meetingId: meeting.id,
      mimeType: meeting.audioMimeType,
      requestId: context.requestId,
    });

    const contextText = buildAudioMeetingMaterialContext({
      userNotes,
      noteAttachmentsContext,
      segmentCommentsContext,
    });

    const { content, provider } = await generateTextWithFallback({
      messages: [
        { role: 'system', content: systemPrompt },
        {
          role: 'user',
          content: [
            {
              type: 'text',
              text: `会议标题：${meeting.title || '未命名会议'}\n\n以下是用户补充上下文：\n${contextText}\n\n请根据原始音频和补充上下文输出结构化会议纪要。`,
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

    const now = new Date();
    const model = resolveAudioEnhanceModel(provider);
    await prisma.meeting.update({
      where: { id: meeting.id },
      data: {
        audioEnhancedNotes: content,
        audioEnhancedNotesStatus: 'ready',
        audioEnhancedNotesError: '',
        audioEnhancedNotesUpdatedAt: now,
        audioEnhancedNotesProvider: provider,
        audioEnhancedNotesModel: model,
      },
    });

    return jsonResponse(context, {
      content,
      provider,
      model,
      status: 'ready',
      updatedAt: now.toISOString(),
    });
  } catch (error) {
    const message =
      error instanceof Error ? `音频 AI 笔记生成失败：${error.message}` : '音频 AI 笔记生成失败，请稍后重试。';
    if (meetingId) {
      await markAudioEnhanceFailure(meetingId, message);
    }
    return errorResponse(context, 502, message, error);
  }
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
  const audioBuffer = await readFile(getMeetingAudioPath(meetingId));

  if (audioBuffer.byteLength <= INLINE_AUDIO_MAX_BYTES) {
    return {
      type: 'audio' as const,
      mimeType,
      data: audioBuffer.toString('base64'),
    };
  }

  if (!process.env.GEMINI_API_KEY) {
    throw new Error('会议音频超过 18 MB，当前未配置直连 Gemini，无法稳定处理该音频。');
  }

  const fileUri = await uploadGeminiAudioFile({
    buffer: audioBuffer,
    mimeType,
    displayName: `meeting-${meetingId}-${requestId}`,
  });

  return {
    type: 'file_audio' as const,
    mimeType,
    fileUri,
  };
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
