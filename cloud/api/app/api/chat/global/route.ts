import { NextRequest } from 'next/server';
import { createRequestContext, textResponse } from '@/lib/api-error';
import { buildGlobalChatContextMessage } from '@/lib/meeting-ai-context';
import { generateTextWithFallback, hasAvailableLlm } from '@/lib/llm-provider';
import { retrieveGlobalMeetingContext, type GlobalChatFilters } from '@/lib/global-chat';
import { selectRetrievalResult } from '@/lib/global-chat-selection';
import type { PromptOptions } from '@/lib/types';

type PromptOptionsInput = Partial<PromptOptions> | undefined;

function createTextStream(text: string): ReadableStream<Uint8Array> {
  const encoder = new TextEncoder();
  let interval: ReturnType<typeof setInterval> | null = null;
  let isClosed = false;

  const cleanup = () => {
    isClosed = true;
    if (interval) {
      clearInterval(interval);
      interval = null;
    }
  };

  return new ReadableStream({
    start(controller) {
      const chars = text.split('');
      let i = 0;
      interval = setInterval(() => {
        if (isClosed) {
          cleanup();
          return;
        }

        if (i < chars.length) {
          try {
            controller.enqueue(encoder.encode(chars[i]));
            i++;
          } catch {
            cleanup();
          }
        } else {
          cleanup();
          try {
            controller.close();
          } catch {
            cleanup();
          }
        }
      }, 8);
    },
    cancel() {
      cleanup();
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

function buildGlobalChatSystemPrompt(options: PromptOptions): string {
  const styleMap: Record<PromptOptions['outputStyle'], string> = {
    简洁: '回答尽量精炼，优先给出结论。',
    平衡: '在完整性与简洁性之间保持平衡。',
    详细: '回答时补充必要背景、原因和前后文。',
    行动导向: '回答优先给出可执行建议和下一步安排。',
  };

  const actionRule = options.includeActionItems
    ? '当问题涉及执行安排时，尽量提炼行动项。'
    : '除非用户明确要求，不主动输出行动项。';

  const basePrompt = `你是一位跨工作区知识助手。你会收到历史会议与资料的检索结果（带来源编号 S1/S2/...）。

回答要求：
1. 只能使用提供的检索内容回答，不要臆造未出现的信息。
2. ${styleMap[options.outputStyle]}
3. ${actionRule}
4. 回答中尽量在关键结论后标注来源编号（例如：[S1]、[S2]）。
5. 使用中文回答。`;

  return basePrompt;
}

function formatSources(
  sources: Array<{ ref: string; type: 'meeting' | 'asset'; title: string; date: string }>
) {
  if (sources.length === 0) return '参考来源：无';
  const lines = sources.map((s) => {
    const dateText = new Date(s.date).toLocaleString('zh-CN', { hour12: false });
    return `- [${s.ref}] ${s.type === 'meeting' ? '会议' : '资料'}：${s.title}（${dateText}）`;
  });
  return `参考来源：\n${lines.join('\n')}`;
}

function buildNoResultMessage(filters: GlobalChatFilters): string {
  const conditions: string[] = [];
  if (filters.dateFrom) conditions.push(`开始时间 >= ${filters.dateFrom}`);
  if (filters.dateTo) conditions.push(`结束时间 <= ${filters.dateTo}`);
  if (filters.collectionId) {
    conditions.push(
      filters.collectionId === '__ungrouped'
        ? '仅未归类会议'
        : `Collection = ${filters.collectionId}`
    );
  }

  if (conditions.length === 0) {
      return '未检索到可用会议或资料。请先保存会议记录或导入资料后再提问。';
  }
  return `在当前筛选条件下未检索到会议或资料：${conditions.join('，')}。请调整筛选条件后重试。`;
}

export async function POST(req: NextRequest) {
  const context = createRequestContext(req, '/api/chat/global');

  try {
    const {
      question,
      chatHistory,
      filters,
      localRetrievalContext,
      localRetrievalSources,
      localCommentContext,
      promptOptions,
      llmRuntimeConfig,
      recipePrompt,
      templatePrompt,
    } =
      await req.json();
    const q = (question || '').trim();
    if (!q) {
      return textResponse(
        context,
        JSON.stringify({
          error: '问题不能为空',
          requestId: context.requestId,
          route: context.route,
        }),
        {
          status: 400,
          headers: { 'Content-Type': 'application/json; charset=utf-8' },
        }
      );
    }

    const fallbackRetrieval = await retrieveGlobalMeetingContext(q, (filters || {}) as GlobalChatFilters);
    const retrieval = selectRetrievalResult({
      localRetrievalContext,
      localRetrievalSources,
      fallback: fallbackRetrieval,
    });

    if (retrieval.sources.length === 0) {
      return textResponse(context, buildNoResultMessage((filters || {}) as GlobalChatFilters), {
        headers: { 'Content-Type': 'text/plain; charset=utf-8' },
      });
    }

    if (!hasAvailableLlm(llmRuntimeConfig)) {
      const demo = `当前为 Demo 模式，已检索到 ${retrieval.sources.length} 场相关会议。\n\n你可以配置默认 LLM 或 OpenAI 兼容 API Key 后获得真实模型回答。\n\n${formatSources(retrieval.sources)}`;
      return textResponse(context, createTextStream(demo), {
        headers: { 'Content-Type': 'text/plain; charset=utf-8' },
      });
    }

    const options = normalizePromptOptions(promptOptions);
    const systemPrompt = buildGlobalChatSystemPrompt(options);

    const messages = [
      { role: 'system', content: systemPrompt },
      {
        role: 'user',
        content: `以下是检索到的历史会议上下文：\n\n${buildGlobalChatContextMessage({
          retrievalContext: retrieval.context,
          localCommentContext: localRetrievalContext ? undefined : localCommentContext,
        })}`,
      },
      {
        role: 'assistant',
        content: '我已读取这些历史会议上下文，请继续提问。',
      },
      ...((recipePrompt || templatePrompt)
        ? [{ role: 'system' as const, content: `当前任务 Recipe 指令：${String(recipePrompt || templatePrompt).trim()}` }]
        : []),
      ...(chatHistory || []).map((m: { role: string; content: string }) => ({
        role: m.role,
        content: m.content,
      })),
      { role: 'user', content: q },
    ];

    const { content, provider } = await generateTextWithFallback({
      messages,
      temperature: 0.4,
      maxTokens: 4096,
      runtimeConfig: llmRuntimeConfig,
    });

    const fullContent = `${content.trim()}\n\n---\n${formatSources(retrieval.sources)}`;
    const stream = createTextStream(fullContent);

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
        error:
          error instanceof Error
            ? `跨会议 AI 对话失败：${error.message}`
            : '跨会议 AI 对话失败，请稍后重试。',
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
