import { NextRequest } from 'next/server';
import { requireAuthenticatedRequest } from '@/lib/api-auth';
import { createRequestContext, textResponse } from '@/lib/api-error';
import {
  buildMeetingChatSystemPrompt,
  normalizePromptOptions,
} from '@/lib/chat-prompts';
import { buildMeetingMaterialContext } from '@/lib/meeting-ai-context';
import {
  generateTextWithFallback,
  hasAvailableLlm,
  resolveLlmRequestPolicy,
} from '@/lib/llm-provider';

const CHAT_MAX_TOKENS = 1_536;

function createTextStream(text: string): ReadableStream<Uint8Array> {
  const encoder = new TextEncoder();
  return new ReadableStream({
    start(controller) {
      const chars = text.split('');
      let i = 0;
      const interval = setInterval(() => {
        if (i < chars.length) {
          controller.enqueue(encoder.encode(chars[i]));
          i++;
        } else {
          clearInterval(interval);
          controller.close();
        }
      }, 8);
    },
  });
}

export async function POST(req: NextRequest) {
  const context = createRequestContext(req, '/api/chat');
  const auth = await requireAuthenticatedRequest(req, context);

  if (auth instanceof Response) {
    return auth;
  }

  try {
    const {
      transcript,
      userNotes,
      enhancedNotes,
      noteAttachmentsContext,
      segmentCommentsContext,
      chatHistory,
      question,
      recipePrompt,
      templatePrompt,
      promptOptions,
      llmRuntimeConfig,
    } = await req.json();

    if (!hasAvailableLlm(llmRuntimeConfig)) {
      // Demo 模式
      const demoResponse = getDemoResponse(question);
      const stream = createTextStream(demoResponse);
      return textResponse(context, stream, {
        headers: { 'Content-Type': 'text/plain; charset=utf-8' },
      });
    }

    const options = normalizePromptOptions(promptOptions);
    const systemPrompt = buildMeetingChatSystemPrompt(options, recipePrompt || templatePrompt);

    const contextMessage = buildMeetingMaterialContext({
      transcript,
      userNotes,
      enhancedNotes,
      noteAttachmentsContext,
      segmentCommentsContext,
    });

    const messages = [
      { role: 'system', content: systemPrompt },
      { role: 'user', content: `以下是会议上下文：\n${contextMessage}` },
      {
        role: 'assistant',
        content: '好的，我已了解本次会议的完整内容。请问有什么需要帮您分析或解答的？',
      },
      ...(chatHistory || []).map((m: { role: string; content: string }) => ({
        role: m.role,
        content: m.content,
      })),
      { role: 'user', content: question },
    ];
    const requestPolicy = resolveLlmRequestPolicy('chat');

    const { content, provider } = await generateTextWithFallback({
      messages,
      temperature: 0.5,
      maxTokens: CHAT_MAX_TOKENS,
      timeoutMs: requestPolicy.timeoutMs,
      retries: requestPolicy.retries,
      runtimeConfig: llmRuntimeConfig,
    });

    const stream = createTextStream(content);

    return textResponse(context, stream, {
      headers: {
        'Content-Type': 'text/plain; charset=utf-8',
        'X-LLM-Provider': provider,
      },
    });
  } catch (error) {
    return textResponse(
      context,
      JSON.stringify({
        error: error instanceof Error ? `会议对话失败：${error.message}` : '会议对话失败，请稍后重试。',
        requestId: context.requestId,
        route: context.route,
      }),
      {
        status: 502,
        headers: { 'Content-Type': 'application/json; charset=utf-8' },
      }
    );
  }
}

function getDemoResponse(question: string): string {
  if (question.includes('行动') || question.includes('待办') || question.includes('TODO')) {
    return '根据会议内容，主要行动项包括：\n\n1. 配置 AiHubMix API Key\n2. 测试实时语音转写\n3. 完善模版系统\n\n当前为 Demo 模式，配置可用的 AiHubMix API 密钥后将基于实际会议内容回答。';
  }
  if (question.includes('总结') || question.includes('摘要')) {
    return '本次会议的核心内容如下。\n\n会议讨论了多项议题，各参会者充分表达了意见并达成初步共识。\n\n当前为 Demo 模式。';
  }
  return `关于您的问题「${question}」，基于当前会议记录的分析结果将在此显示。\n\n配置 AiHubMix API 密钥后，将使用真实 AI 基于转写和笔记内容回答您的问题。\n\n当前为 Demo 模式，请配置 API 密钥启用完整功能。`;
}
