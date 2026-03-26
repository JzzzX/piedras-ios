import { NextRequest } from 'next/server';
import { requireAuthenticatedRequest } from '@/lib/api-auth';
import { createRequestContext, textResponse } from '@/lib/api-error';
import { buildMeetingMaterialContext } from '@/lib/meeting-ai-context';
import { generateTextWithFallback, hasAvailableLlm } from '@/lib/llm-provider';
import type { PromptOptions } from '@/lib/types';

type PromptOptionsInput = Partial<PromptOptions> | undefined;

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

function normalizePromptOptions(input: PromptOptionsInput): PromptOptions {
  return {
    meetingType: input?.meetingType || '通用',
    outputStyle: input?.outputStyle || '平衡',
    includeActionItems: input?.includeActionItems ?? true,
  };
}

function buildChatSystemPrompt(
  options: PromptOptions,
  recipePrompt?: string
): string {
  const styleMap: Record<PromptOptions['outputStyle'], string> = {
    简洁: '回答尽量精炼，优先给出结论。',
    平衡: '在完整性与简洁性之间保持平衡。',
    详细: '回答时补充必要背景、原因和前后文。',
    行动导向: '回答优先给出可执行建议和下一步安排。',
  };

  const actionRule = options.includeActionItems
    ? '当问题与执行相关时，请明确给出行动项（负责人/截止日期可标注待定）。'
    : '除非用户明确要求，不主动输出行动项。';

  const basePrompt = `你是一位智能会议助手。当前会议类型：${options.meetingType}。

你可以访问会议转写、用户笔记和 AI 纪要。请基于这些信息准确回答问题；若信息不足，请明确说明不足点。

回答要求：
1. ${styleMap[options.outputStyle]}
2. ${actionRule}
3. 使用中文回答，不要臆造会议中不存在的信息。`;

  const sections = [basePrompt];
  if (recipePrompt) {
    sections.push(`当前任务 Recipe 指令：${recipePrompt.trim()}`);
  }

  return sections.join('\n\n');
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
    const systemPrompt = buildChatSystemPrompt(options, recipePrompt || templatePrompt);

    const contextMessage = buildMeetingMaterialContext({
      transcript,
      userNotes,
      enhancedNotes,
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

    const { content, provider } = await generateTextWithFallback({
      messages,
      temperature: 0.5,
      maxTokens: 4096,
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
    return '根据会议内容，主要的行动项包括：\n\n1. 配置默认 LLM 或 OpenAI 兼容凭证\n2. 测试实时语音转写\n3. 完善模版系统\n\n> *当前为 Demo 模式，配置可用的 LLM API 密钥后将基于实际会议内容回答*';
  }
  if (question.includes('总结') || question.includes('摘要')) {
    return '本次会议的核心内容总结如下：\n\n会议讨论了多项议题，各参会者充分表达了意见并达成初步共识。\n\n> *当前为 Demo 模式*';
  }
  return `关于您的问题「${question}」：\n\n基于当前会议记录的分析结果将在此显示。配置默认 LLM 或 OpenAI 兼容 API 密钥后，将使用真实 AI 基于转写和笔记内容回答您的问题。\n\n> *当前为 Demo 模式，请配置 API 密钥启用完整功能*`;
}
