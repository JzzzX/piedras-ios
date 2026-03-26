import { NextRequest } from 'next/server';
import { requireAuthenticatedRequest } from '@/lib/api-auth';
import { createRequestContext, errorResponse, jsonResponse } from '@/lib/api-error';
import { generateTextWithFallback, hasAvailableLlm } from '@/lib/llm-provider';
import type { PromptOptions } from '@/lib/types';

const SHORT_MEMO_THRESHOLD_SECONDS = 45;
const MAX_TITLE_LENGTH = 18;

function normalizePromptOptions(input?: Partial<PromptOptions>): PromptOptions {
  return {
    meetingType: input?.meetingType || '通用',
    outputStyle: input?.outputStyle || '平衡',
    includeActionItems: input?.includeActionItems ?? true,
  };
}

function recordingTitle(dateInput?: string): string {
  const date = dateInput ? new Date(dateInput) : new Date();
  const formatter = new Intl.DateTimeFormat('zh-CN', {
    month: 'numeric',
    day: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
    hour12: false,
  });

  return `${formatter.format(date)} 录音`;
}

function sanitizeGeneratedTitle(rawTitle: string): string {
  return rawTitle
    .replace(/[\n\r#>*`]+/g, ' ')
    .replace(/\s+/g, ' ')
    .trim()
    .slice(0, MAX_TITLE_LENGTH);
}

function cleanTranscript(transcript: string): string {
  return transcript
    .replace(/\[[^\]]+\]/g, ' ')
    .replace(/\r\n/g, '\n')
    .replace(/\r/g, '\n');
}

function compactTranscript(transcript: string): string {
  return cleanTranscript(transcript)
    .replace(/[，。！？、,.!?:：；;（）()“”"'‘’·\-\[\]]+/g, ' ')
    .replace(/\s+/g, '')
    .trim();
}

function stripLeadingPhrases(input: string): string {
  const leadingPhrases = [
    '我们今天主要讨论一下',
    '我们今天主要聊一下',
    '今天主要讨论一下',
    '今天主要聊一下',
    '我们今天讨论一下',
    '我们今天聊一下',
    '今天讨论一下',
    '今天聊一下',
    '我们来聊聊',
    '我想聊聊',
    '我们先看一下',
    '我们先聊一下',
    '我们先聊聊',
    '我们先把',
    '先看一下',
    '先聊一下',
    '先聊聊',
    '先把',
    '主要是关于',
    '就是关于',
    '关于',
    '主要聊',
    '讨论',
    '聊一下',
    '聊聊',
    '说一下',
    '想说',
    '就是说',
    '就是',
    '那个',
    '这个',
    '嗯',
    '啊',
  ];

  let value = input.trim();
  let didStrip = true;

  while (didStrip) {
    didStrip = false;
    for (const phrase of leadingPhrases) {
      if (value.startsWith(phrase)) {
        value = value.slice(phrase.length).trim();
        didStrip = true;
      }
    }
  }

  return value;
}

function stripTrailingPhrases(input: string): string {
  const trailingPhrases = [
    '的安排',
    '这个安排',
    '这件事情',
    '这个事情',
    '这个问题',
    '的问题',
    '一下',
  ];

  let value = input.trim();
  let didStrip = true;

  while (didStrip) {
    didStrip = false;
    for (const phrase of trailingPhrases) {
      if (value.endsWith(phrase)) {
        value = value.slice(0, -phrase.length).trim();
        didStrip = true;
      }
    }
  }

  return value;
}

function buildKeyPhraseTitle(transcript: string): string | null {
  const sentences = cleanTranscript(transcript)
    .split(/[。！？!?；;\n]+/)
    .map((sentence) => sentence.trim())
    .filter(Boolean)
    .slice(0, 3);

  for (const sentence of sentences) {
    const cleaned = stripTrailingPhrases(
      stripLeadingPhrases(
        sentence
          .replace(/[，。！？、,.!?:：；;（）()“”"'‘’·\-\[\]]+/g, ' ')
          .replace(/\s+/g, '')
          .trim()
      )
    );

    const candidate = sanitizeGeneratedTitle(cleaned);
    if (candidate.length >= 4) {
      return candidate;
    }
  }

  return null;
}

function isLowInformation(transcript: string): boolean {
  const finalSegments = cleanTranscript(transcript)
    .split('\n')
    .map((line) => line.trim())
    .filter(Boolean);

  return finalSegments.length < 2 || compactTranscript(transcript).length < 12;
}

function buildHeuristicTitle(transcript: string, durationSeconds?: number, meetingDate?: string): string {
  const keyPhrase = buildKeyPhraseTitle(transcript);
  if (keyPhrase) {
    return keyPhrase;
  }

  if ((durationSeconds || 0) > 0 && (durationSeconds || 0) <= SHORT_MEMO_THRESHOLD_SECONDS) {
    const minutes = Math.floor((durationSeconds || 0) / 60)
      .toString()
      .padStart(2, '0');
    const seconds = Math.floor((durationSeconds || 0) % 60)
      .toString()
      .padStart(2, '0');
    return `语音备忘 ${minutes}:${seconds}`;
  }

  if (isLowInformation(transcript)) {
    return recordingTitle(meetingDate);
  }

  return recordingTitle(meetingDate);
}

export async function POST(req: NextRequest) {
  const context = createRequestContext(req, '/api/meetings/title');
  const auth = await requireAuthenticatedRequest(req, context);

  if (auth instanceof Response) {
    return auth;
  }

  try {
    const { transcript, durationSeconds, meetingDate, promptOptions, llmRuntimeConfig } = await req.json();
    const normalizedTranscript = (transcript || '').trim();

    if (!normalizedTranscript) {
      return jsonResponse(context, {
        title: buildHeuristicTitle('', durationSeconds, meetingDate),
        provider: 'demo',
      });
    }

    if (!hasAvailableLlm(llmRuntimeConfig)) {
      return jsonResponse(context, {
        title: buildHeuristicTitle(normalizedTranscript, durationSeconds, meetingDate),
        provider: 'demo',
      });
    }

    const options = normalizePromptOptions(promptOptions);

    const { content, provider } = await generateTextWithFallback({
      messages: [
        {
          role: 'system',
          content: `你是一位会议标题生成助手。请根据会议转写内容生成一个简短、清晰、可读的中文会议标题。

要求：
1. 只输出标题本身，不要解释。
2. 长度尽量控制在 8-18 个汉字，理想长度 12-18。
3. 不要使用书名号、引号、句号等多余标点。
4. 标题应准确体现会议主题或主要议题。
5. 不要写成完整句子，不要写成摘要。
 6. 当前会议类型：${options.meetingType}。`,
        },
        {
          role: 'user',
          content: `请为以下会议内容生成标题：\n\n${normalizedTranscript.slice(0, 3000)}`,
        },
      ],
      temperature: 0.2,
      maxTokens: 80,
      runtimeConfig: llmRuntimeConfig,
    });

    const title = sanitizeGeneratedTitle(content);

    return jsonResponse(context, {
      title: title || buildHeuristicTitle(normalizedTranscript, durationSeconds, meetingDate),
      provider,
    });
  } catch (error) {
    return errorResponse(
      context,
      502,
      error instanceof Error ? `标题生成失败：${error.message}` : '标题生成失败，请稍后重试。',
      error
    );
  }
}
