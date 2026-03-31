import { NextRequest } from 'next/server';
import { requireAuthenticatedRequest } from '@/lib/api-auth';
import { createRequestContext, errorResponse, jsonResponse } from '@/lib/api-error';
import { generateTextWithFallback, hasAvailableLlm } from '@/lib/llm-provider';
import {
  buildHeuristicTitle,
  buildTitleSystemPrompt,
  normalizePromptOptions,
  sanitizeGeneratedTitle,
  shouldRejectGeneratedTitle,
} from '@/lib/meeting-title';

const TITLE_TIMEOUT_MS = 8_000;

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
          content: buildTitleSystemPrompt(options.meetingType),
        },
        {
          role: 'user',
          content: `请为以下会议内容生成标题：\n\n${normalizedTranscript.slice(0, 3000)}`,
        },
      ],
      temperature: 0.2,
      maxTokens: 80,
      timeoutMs: TITLE_TIMEOUT_MS,
      retries: 0,
      runtimeConfig: llmRuntimeConfig,
    });

    const title = sanitizeGeneratedTitle(content);

    return jsonResponse(context, {
      title:
        title && !shouldRejectGeneratedTitle(title)
          ? title
          : buildHeuristicTitle(normalizedTranscript, durationSeconds, meetingDate),
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
