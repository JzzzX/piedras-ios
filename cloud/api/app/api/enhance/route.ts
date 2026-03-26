import { NextRequest } from 'next/server';
import { requireAuthenticatedRequest } from '@/lib/api-auth';
import { createRequestContext, errorResponse, jsonResponse } from '@/lib/api-error';
import { buildMeetingMaterialContext } from '@/lib/meeting-ai-context';
import { generateTextWithFallback, hasAvailableLlm } from '@/lib/llm-provider';
import type { PromptOptions } from '@/lib/types';

type PromptOptionsInput = Partial<PromptOptions> | undefined;

function normalizePromptOptions(input: PromptOptionsInput): PromptOptions {
  return {
    meetingType: input?.meetingType || '通用',
    outputStyle: input?.outputStyle || '平衡',
    includeActionItems: input?.includeActionItems ?? true,
  };
}

function buildEnhanceSystemPrompt(
  options: PromptOptions,
  recipePrompt?: string
): string {
  const styleMap: Record<PromptOptions['outputStyle'], string> = {
    简洁: '表达尽量精炼，优先输出结论和关键点。',
    平衡: '在信息完整和阅读效率之间保持平衡。',
    详细: '尽可能保留背景、分歧和上下文细节。',
    行动导向: '优先输出可执行结论，强调负责人、截止时间与依赖关系。',
  };

  const actionRule = options.includeActionItems
    ? '“行动项”章节必须输出，且每条至少包含：事项、负责人（未知可写待定）、建议截止日期（未知可写待定）。'
    : '“行动项”章节仅在会议中有明确待办时输出；若无可写“无明确行动项”。';

  const basePrompt = `你是一位专业的会议记录助手。当前会议类型：${options.meetingType}。

请根据输入内容生成结构化会议纪要，输出格式如下：

## 会议摘要
（3-5 句话概括）

## 关键讨论点
（按主题分点整理）

## 决策事项
（明确达成的决定）

## 行动项
（按要求输出）

## 待确认事项
（需要后续跟进确认的问题）

写作要求：
1. 用户手写要点优先，转写内容用于补充证据和上下文。
2. ${styleMap[options.outputStyle]}
3. ${actionRule}
4. 使用中文输出，不要捏造会议未出现的信息。`;

  const sections = [];
  if (recipePrompt) {
    sections.push(recipePrompt.trim());
    sections.push(`补充约束：${basePrompt}`);
  } else {
    sections.push(basePrompt);
  }

  return sections.join('\n\n');
}

export async function POST(req: NextRequest) {
  const context = createRequestContext(req, '/api/enhance');
  const auth = await requireAuthenticatedRequest(req, context);

  if (auth instanceof Response) {
    return auth;
  }

  try {
    const {
      transcript,
      userNotes,
      meetingTitle,
      segmentCommentsContext,
      recipePrompt,
      promptOptions,
      llmRuntimeConfig,
    } =
      await req.json();

    const resolvedRecipePrompt = typeof recipePrompt === 'string' ? recipePrompt.trim() : '';

    if (!hasAvailableLlm(llmRuntimeConfig)) {
      // Demo 模式：无 API Key 时返回模拟结果
      return jsonResponse(context, {
        content: generateDemoEnhancedNotes(transcript, userNotes, meetingTitle),
        provider: 'demo',
      });
    }

    const options = normalizePromptOptions(promptOptions);
    const systemPrompt = buildEnhanceSystemPrompt(options, resolvedRecipePrompt);

    const { content, provider } = await generateTextWithFallback({
      messages: [
        { role: 'system', content: systemPrompt },
        {
          role: 'user',
          content: `会议标题：${meetingTitle || '未命名会议'}

${buildMeetingMaterialContext({
  transcript,
  userNotes,
  segmentCommentsContext,
})}

请根据以上内容生成结构化会议纪要。`,
        },
      ],
      temperature: 0.3,
      maxTokens: 4096,
      runtimeConfig: llmRuntimeConfig,
    });

    return jsonResponse(context, { content, provider });
  } catch (error) {
    return errorResponse(
      context,
      502,
      error instanceof Error ? `AI 后处理失败：${error.message}` : 'AI 后处理失败，请稍后重试。',
      error
    );
  }
}

function generateDemoEnhancedNotes(
  transcript: string,
  userNotes: string,
  meetingTitle: string
): string {
  return `## 会议摘要
本次「${meetingTitle || '未命名会议'}」讨论了多项重要议题。参会者就关键问题进行了深入交流，并达成了初步共识。

## 关键讨论点
${transcript ? '- 基于转写内容的讨论要点（Demo 模式）' : '- 暂无转写内容'}
${userNotes ? '- 基于用户笔记的重点' : ''}

## 决策事项
- 此为 Demo 模式生成的示例内容
- 配置默认 LLM 或 OpenAI 兼容 API Key 后将使用真实 AI 生成

## 行动项
- [ ] 配置默认 LLM 或 OpenAI 兼容 API Key
- [ ] 配置阿里云 ASR 相关密钥以启用实时转写

## 待确认事项
- 完整 AI 功能需要配置相应的 API 密钥

> *提示：当前为 Demo 模式。配置 .env.local 中的 API 密钥后可启用完整 AI 能力。*`;
}
