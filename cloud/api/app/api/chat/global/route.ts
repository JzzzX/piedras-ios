import { NextRequest } from 'next/server';
import { requireAuthenticatedRequest } from '@/lib/api-auth';
import { createRequestContext, textResponse } from '@/lib/api-error';
import {
  buildGlobalChatSystemPrompt,
  normalizePromptOptions,
} from '@/lib/chat-prompts';
import { buildGlobalChatContextMessage } from '@/lib/meeting-ai-context';
import {
  generateTextWithFallback,
  hasAvailableLlm,
  resolveLlmRequestPolicy,
} from '@/lib/llm-provider';
import { retrieveGlobalMeetingContext, type GlobalChatFilters } from '@/lib/global-chat';
import { selectRetrievalResult } from '@/lib/global-chat-selection';

const GLOBAL_CHAT_MAX_TOKENS = 1_536;

function formatSources(
  sources: Array<{ ref: string; type: 'meeting' | 'asset'; title: string; date: string }>
) {
  if (sources.length === 0) return '参考来源：无';
  const lines = sources.map((s) => {
    const dateText = new Date(s.date).toLocaleString('zh-CN', { hour12: false });
    return `[${s.ref}] ${s.type === 'meeting' ? '会议' : '资料'}：${s.title}（${dateText}）`;
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
        ? '仅未归类笔记'
        : `文件夹 = ${filters.collectionId}`
    );
  }

  if (conditions.length === 0) {
    return '未检索到可用会议或资料。请先保存会议记录或导入资料后再提问。';
  }
  return `在当前筛选条件下未检索到会议或资料：${conditions.join('，')}。请调整筛选条件后重试。`;
}

export async function POST(req: NextRequest) {
  const context = createRequestContext(req, '/api/chat/global');
  const auth = await requireAuthenticatedRequest(req, context);

  if (auth instanceof Response) {
    return auth;
  }

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

    const scopedFilters = {
      ...(filters || {}),
      workspaceId: auth.workspace.id,
    } as GlobalChatFilters;

    const fallbackRetrieval = await retrieveGlobalMeetingContext(q, scopedFilters);
    const retrieval = selectRetrievalResult({
      localRetrievalContext,
      localRetrievalSources,
      fallback: fallbackRetrieval,
    });

    if (retrieval.sources.length === 0) {
      return textResponse(context, buildNoResultMessage(scopedFilters), {
        headers: { 'Content-Type': 'text/plain; charset=utf-8' },
      });
    }

    if (!hasAvailableLlm(llmRuntimeConfig)) {
      const demo = `当前为 Demo 模式，已检索到 ${retrieval.sources.length} 场相关会议。\n\n你可以配置 AiHubMix API Key 后获得真实模型回答。\n\n${formatSources(retrieval.sources)}`;
      return textResponse(context, demo, {
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
    const requestPolicy = resolveLlmRequestPolicy('globalChat');

    const { content, provider } = await generateTextWithFallback({
      messages,
      temperature: 0.4,
      maxTokens: GLOBAL_CHAT_MAX_TOKENS,
      timeoutMs: requestPolicy.timeoutMs,
      retries: requestPolicy.retries,
      runtimeConfig: llmRuntimeConfig,
    });

    const fullContent = `${content.trim()}\n\n${formatSources(retrieval.sources)}`;

    return textResponse(context, fullContent, {
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
